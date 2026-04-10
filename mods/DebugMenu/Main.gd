extends CanvasLayer

var gameData = load("res://Resources/GameData.tres")

var panel: Panel
var cb_god: CheckBox
var cb_stamina: CheckBox
var cb_ailments: CheckBox
var cb_npc: CheckBox
var cb_weight: CheckBox
var sld_speed: HSlider
var lbl_speed_val: Label
var sld_jump: HSlider
var lbl_jump_val: Label
var lbl_dbg: Label

var _controller: Node = null
var _interface: Node = null
var _last_scene: Node = null
var _orig_walk := 2.5
var _orig_sprint := 5.0
var _orig_jump := 7.0
var _orig_crouch := 1.0
var _orig_carry := 10.0
var _carry_boosted := false

const BIG_CARRY := 99999.0

func _ready() -> void:
    panel = Panel.new()
    panel.self_modulate = Color(0, 0, 0, 0.85)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    panel.custom_minimum_size = Vector2(240, 0)
    panel.position = Vector2(10, 10)
    add_child(panel)

    var vbox := VBoxContainer.new()
    vbox.position = Vector2(10, 10)
    vbox.custom_minimum_size = Vector2(220, 0)
    panel.add_child(vbox)

    _add_label(vbox, "=== DEBUG MENU (F4) ===")

    cb_god = _add_checkbox(vbox, "God Mode")
    cb_stamina = _add_checkbox(vbox, "Infinite Stamina")
    cb_ailments = _add_checkbox(vbox, "No Ailments")
    cb_npc = _add_checkbox(vbox, "NPC Ignore Player")
    cb_weight = _add_checkbox(vbox, "Unlimited Weight")

    var speed_row := _add_slider_row(vbox, "Speed", 1.0, 20.0, 1.0)
    sld_speed = speed_row[0]
    lbl_speed_val = speed_row[1]
    sld_speed.value_changed.connect(_on_slider_changed)

    var jump_row := _add_slider_row(vbox, "Jump", 1.0, 10.0, 1.0)
    sld_jump = jump_row[0]
    lbl_jump_val = jump_row[1]
    sld_jump.value_changed.connect(_on_slider_changed)

    var btn_unstick := Button.new()
    btn_unstick.text = "Unstick (bump up)"
    btn_unstick.pressed.connect(_on_unstick)
    vbox.add_child(btn_unstick)

    lbl_dbg = Label.new()
    lbl_dbg.add_theme_font_size_override("font_size", 10)
    vbox.add_child(lbl_dbg)

    panel.hide()

func _add_label(parent: Node, text: String) -> Label:
    var l := Label.new()
    l.text = text
    parent.add_child(l)
    return l

func _add_checkbox(parent: Node, text: String) -> CheckBox:
    var cb := CheckBox.new()
    cb.text = text
    parent.add_child(cb)
    return cb

func _add_slider_row(parent: Node, label_text: String, min_val: float, max_val: float, step: float) -> Array:
    var row := HBoxContainer.new()
    parent.add_child(row)

    var lbl := Label.new()
    lbl.text = label_text + ":"
    lbl.custom_minimum_size = Vector2(48, 0)
    row.add_child(lbl)

    var sld := HSlider.new()
    sld.min_value = min_val
    sld.max_value = max_val
    sld.step = step
    sld.value = min_val
    sld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(sld)

    var val_lbl := Label.new()
    val_lbl.text = "1x"
    val_lbl.custom_minimum_size = Vector2(32, 0)
    row.add_child(val_lbl)

    return [sld, val_lbl]

func _on_slider_changed(_value: float) -> void:
    lbl_speed_val.text = "%.0fx" % sld_speed.value
    lbl_jump_val.text = "%.0fx" % sld_jump.value

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
        var scene = get_tree().current_scene
        if scene == null:
            return
        if scene.scene_file_path == "res://Scenes/Menu.tscn":
            return
        panel.visible = not panel.visible
        if panel.visible:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        else:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# we do it per frame stylee
func _process(_delta: float) -> void:
    var scene = get_tree().current_scene
    if scene == null or gameData.menu or gameData.isTransitioning or gameData.isCaching:
        if panel.visible:
            panel.hide()
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        return

    # Invalidate cache on scene change
    if scene != _last_scene:
        _controller = null
        _interface = null
        _carry_boosted = false
        _last_scene = scene

    # God mode
    if cb_god.button_pressed:
        gameData.health = 100.0
        gameData.energy = 100.0
        gameData.hydration = 100.0
        gameData.mental = 100.0
        gameData.temperature = 100.0
        gameData.oxygen = 100.0
        gameData.isDead = false
        gameData.isFalling = false

    # Infinite stamina
    if cb_stamina.button_pressed:
        gameData.bodyStamina = 100.0
        gameData.armStamina = 100.0

    # No ailments
    if cb_ailments.button_pressed:
        gameData.bleeding = false
        gameData.fracture = false
        gameData.burn = false
        gameData.frostbite = false
        gameData.insanity = false
        gameData.poisoning = false
        gameData.rupture = false
        gameData.headshot = false
        gameData.starvation = false
        gameData.dehydration = false
        gameData.isBurning = false
        gameData.overweight = false

    # Unlimited weight (standalone)
    if cb_weight.button_pressed and not cb_ailments.button_pressed:
        gameData.overweight = false

    # NPC ignore (throttled)
    if Engine.get_process_frames() % 3 == 0 and cb_npc.button_pressed:
        for node in get_tree().get_nodes_in_group("AI"):
            if "playerVisible" in node:
                node.set("playerVisible", false)

    # Find and cache controller
    if _controller == null or not is_instance_valid(_controller):
        _controller = _find_node_with_props(scene, ["walkSpeed", "currentSpeed", "jumpVelocity"])

    if _controller != null:
        # Read originals once per scene
        if _orig_walk == 2.5 and _controller.get("walkSpeed") != _orig_walk * sld_speed.value:
            pass  # already initialised
        # Always read current base from slider-1 state isn't reliable — store on first find
        _apply_controller_values()

        lbl_dbg.text = "walk=%.1f jump=%.1f" % [
            _controller.get("walkSpeed"),
            _controller.get("jumpVelocity"),
        ]
    else:
        lbl_dbg.text = "controller: not found"

    # Carry weight inflation :shocked:
    if cb_weight.button_pressed:
        if _interface == null or not is_instance_valid(_interface):
            _interface = _find_node_with_props(scene, ["baseCarryWeight", "currentInventoryWeight"])
        if _interface != null:
            if not _carry_boosted:
                _orig_carry = _interface.get("baseCarryWeight")
                _carry_boosted = true
            _interface.set("baseCarryWeight", BIG_CARRY)
    elif _carry_boosted and _interface != null and is_instance_valid(_interface):
        _interface.set("baseCarryWeight", _orig_carry)
        _carry_boosted = false

var _ctrl_initialized := false

func _apply_controller_values() -> void:
    if not _ctrl_initialized:
        _orig_walk = _controller.get("walkSpeed")
        _orig_sprint = _controller.get("sprintSpeed") if "sprintSpeed" in _controller else _orig_sprint
        _orig_jump = _controller.get("jumpVelocity")
        _orig_crouch = _controller.get("crouchSpeed") if "crouchSpeed" in _controller else _orig_crouch
        _ctrl_initialized = true

    var speed_mult := sld_speed.value
    _controller.set("walkSpeed", _orig_walk * speed_mult)
    if "sprintSpeed" in _controller:
        _controller.set("sprintSpeed", _orig_sprint * speed_mult)
    if "crouchSpeed" in _controller:
        _controller.set("crouchSpeed", _orig_crouch * speed_mult)

    var jump_mult := sld_jump.value
    _controller.set("jumpVelocity", _orig_jump * jump_mult)

func _on_unstick() -> void:
    if _controller != null and is_instance_valid(_controller):
        _controller.global_position.y += 2.0

func _find_node_with_props(node: Node, props: Array) -> Node:
    var matched := true
    for p in props:
        if not (p in node):
            matched = false
            break
    if matched:
        return node
    for child in node.get_children():
        var result = _find_node_with_props(child, props)
        if result != null:
            return result
    return null
