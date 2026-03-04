extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_thread_pressed() -> void:
	$Gesture.classify_thread()
	print("ready")


func _on_no_thread_pressed() -> void:
	$Gesture.classify()
	print("ready")
	


func _on_gesture_gesture_name(gestureName: StringName, disCloudPoint: float) -> void:
	$CanvasLayer/Label2.text = "Gesture Detected as: " + gestureName
