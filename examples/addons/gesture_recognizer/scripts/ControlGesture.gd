extends Area2D
class_name Gesture

@export var disabled : bool = false

@export_category("Line")

## Line variables
var line = null
@export var capMode : int = 2
@export var minLengthLine : int = 15
@export var lineWidth : int = 6
@export var smooth : int = 3;
@export var lineColor : Color = Color.ALICE_BLUE
@export var widthCurve : Curve = null
@export var lineShader : ShaderMaterial = null

@export_subgroup("Outline")
var outline = null
@export var Outline : bool = true
@export var outlineWidth : int = 6
@export var outlineColor : Color = Color.BLACK
@export var lineCoverLine : bool = false

var onDrawing : bool = false
#puntos
var gestureResource : Gest
var pointsArray
var pointsNorm : Array
var pointsIntegers : Array
const steps : int = 64

#Construct LUT
var LUT: Dictionary 
const maxCoords : int = 1024
const LUTSize : int = 64
const LUTScale : int = maxCoords / LUTSize

#Guardado
@export_subgroup("Create Gesture")
@export var createGesture : bool = false
var create

#Opciones
@export_subgroup("Settings")
@export var touch : bool = false
@export var customButton : bool = false
@export var customButtomUI : String
var earlyAbandoning : bool = true
var lowerBounding : bool = true
@export var customDir : bool = false
@export var customDirUI : String = ""

@export_subgroup("Classify Gesture")
@export var buttonForClassify : bool = false
@export var buttonForClassifyUI : String
@export var ClassifyGesture : bool = false

#Señales
var nameGest
signal gesture_name(gestureName : StringName,  disCloudPoint : float)
signal on_draw_enter()
signal on_draw_exit()
signal line_disappear(points : Array)
var pointsDissapear

#error
var error : bool = false

func classify():
	set_gesture()
	reset_gesture()
	if createGesture: # and line != null:
		create.visible = true
		if pointsArray != null and not pointsArray.is_empty():
			resize_points(pointsArray)
			normalize_points(pointsArray)
			integers_points(pointsNorm)
			LUT_construct()
	else:
		if pointsArray != null and not pointsArray.is_empty():
			# If NOT threaded, we need to process points right here synchronously before classifying
			resize_points(pointsArray)
			normalize_points(pointsArray)
			if !error:
				integers_points(pointsNorm)
				LUT_construct()
			
			if !LUT.is_empty() and !error:
				nameGest = CloudRecognizer.classify(gestureResource, false)
				var distCloud =  CloudRecognizer.dist()
				gesture_name.emit(nameGest, distCloud)
		reset_gesture_data()
	pass

func classify_thread():
	# 1. Main Thread: Extract data from Nodes (Must be on Main Thread)
	if get_node("Line").get_child_count() > 0:
		var children = get_node("Line").get_children()
		for i in range(children.size()):
			pointsArray = append_vec3_array(children[i], i)
			
	reset_gesture()
	
	if createGesture:
		create.visible = true
		if pointsArray != null and not pointsArray.is_empty():
			# If creating a gesture, we still need to process the points synchronously
			resize_points(pointsArray)
			normalize_points(pointsArray)
			integers_points(pointsNorm)
			LUT_construct()
	else:
		# 2. Dispatch heavy math to the worker thread
		if pointsArray != null and not pointsArray.is_empty():
			# Pass a copy of the points so the main thread doesn't accidentally modify them
			WorkerThreadPool.add_task(_run_cloud_recognition_threaded.bind(pointsArray.duplicate(true)))
		else:
			reset_gesture_data()

# Inside your Worker Thread function
func _run_cloud_recognition_threaded(raw_points: Array):
	# 1. Do the heavy lifting (Data preparation)
	resize_points(raw_points)
	normalize_points(pointsArray)
	if error:
		call_deferred("_finalize_classification", "", 0.0)
		return
		
	integers_points(pointsNorm)
	LUT_construct()

	if LUT.is_empty() or error:
		call_deferred("_finalize_classification", "", 0.0)
		return

	# 2. Do the math (No signals inside here!)
	var result_name = CloudRecognizer.classify(gestureResource, true)
	var result_dist = CloudRecognizer.dist()
	
	# 3. Return to Main Thread to emit the signal safely
	call_deferred("_finalize_classification", result_name, result_dist)

# Inside ControlGesture.gd (The script calling the thread)
# This runs on the MAIN THREAD after the math is done
func _finalize_classification(nameGest, distCloud):
	# 1. Check if the node actually exists before touching it
	var cloud_node = get_node_or_null("/root/CloudRecognizer") # Use your actual path
	
	if cloud_node:
		cloud_node.classified_gesture.emit(nameGest)
	else:
		# If it's an Autoload (Singleton), just use the name directly:
		CloudRecognizer.classified_gesture.emit(nameGest)
	
	# 2. Emit your local signal
	gesture_name.emit(nameGest, distCloud)
	reset_gesture_data()
		
func _ready():
	
	if customDir:
		CloudRecognizer.customDir = true
		CloudRecognizer.customDirUI = customDirUI
	
	smooth = maxi(smooth, 1)
	
	connect("input_event", _on_input_event) 
	ClassifyGesture = false
	LUT.clear()
	gestureResource = Gest.new()
	
	if touch:
		customButton = false
	
	CloudRecognizer.earlyAbandoning = earlyAbandoning
	CloudRecognizer.lowerBounding = lowerBounding
	CloudRecognizer.maxCoords = maxCoords
	CloudRecognizer.LUTSize = LUTSize
	CloudRecognizer.LUTScale = LUTScale
	
	if createGesture:
		var node = CanvasLayer.new()
		add_child(node)
		var nn = get_children()[-1]
		var crea = preload("res://addons/gesture_recognizer/others/create.tscn")
		var createInst = crea.instantiate()
		nn.add_child(createInst)
		create = nn.get_node("Create")
		create.visible = false
		var crea2 = preload("res://addons/gesture_recognizer/others/bottom_crear.tscn")
		var create2Inst = crea2.instantiate()
		nn.add_child(create2Inst)
	
	if Outline and !lineCoverLine:
		var outlineNode = Node.new()
		outlineNode.set_name("Outline")
		add_child(outlineNode)
	
	var lineNode = Node.new()
	lineNode.set_name("Line")
	add_child(lineNode)

	pass

func _process(delta):
	
	if ClassifyGesture:
		ClassifyGesture = false
		classify()
	
	if customButton:
		if Input.is_action_just_pressed(customButtomUI):
			drawing()
		if Input.is_action_just_released(customButtomUI):
			stop_drawing()
	
	if onDrawing and is_instance_valid(line): # and ( != get_global_mouse_position()):
		var a : Array = line.get_points();
		if !a.is_empty():
			if a.back() != get_global_mouse_position():
				line.add_point(get_global_mouse_position())
				if Outline:
					outline.add_point(get_global_mouse_position())
		else:
			line.add_point(get_global_mouse_position())
			if Outline:
				outline.add_point(get_global_mouse_position())
	
	if buttonForClassify and Input.is_action_just_pressed(buttonForClassifyUI):
		classify()

func _on_input_event(viewport, event, shape_idx):
	if disabled:
		return
	
	if (event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == 1)):
		if event.pressed:
			drawing()
		elif !event.pressed:
			stop_drawing()

# Update the drawing logic to respect the disabled flag
func drawing():
	if disabled:
		return
	on_draw_enter.emit()
	error = false
	onDrawing = true
	line = Line2D.new()
	# usings the line texture stretch so any shader UV's will work correctly
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	if lineShader != null:
		line.material = lineShader
	line.set_default_color(lineColor)
	line.set_begin_cap_mode(capMode)
	line.set_end_cap_mode(capMode)
	line.set_antialiased(true)
	line.set_width(lineWidth)
	if widthCurve != null:
		line.set_curve(widthCurve)
	if Outline:
		outline = Line2D.new()
		outline.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		outline.set_default_color(outlineColor)
		outline.set_begin_cap_mode(capMode)
		outline.set_end_cap_mode(capMode)
		outline.set_antialiased(true)
		outline.set_width(lineWidth + outlineWidth)
		if lineShader != null:
			outline.material = lineShader
		if widthCurve != null:
			outline.set_curve(widthCurve)
		if !lineCoverLine:
			get_node("Outline").add_child(outline)
		else:
			get_node("Line").add_child(outline)
	get_node("Line").add_child(line)
	pass

func stop_drawing():
	if disabled:
		return
	onDrawing = false
	on_draw_exit.emit()
	if line != null:
		var smoothedPoints = smooth_points(line.get_points())
		line.set_points(smoothedPoints)
		var length : float = 0
		for i in smoothedPoints.size():
			if i != 0:
				length += distance(smoothedPoints[i - 1], smoothedPoints[i])
		if Outline:
			outline.set_points(smoothedPoints)
			if length < minLengthLine:
				outline.queue_free()
			outline = null
		if length < minLengthLine:
			line.queue_free()
	line = null
	pass

func smooth_points(points):
	# Suavizado de Puntos
	var smoothedPoints = []
	var windowSize = smooth

	for i in range(points.size()):
		var sumx = 0.0
		var sumy = 0.0
		var count = 0

		for j in range(max(0, i - windowSize), min(points.size(), i + windowSize)):
			sumx += points[j].x
			sumy += points[j].y
			count += 1

		smoothedPoints.append(Vector2(sumx / count, sumy / count))
		
	
	queue_redraw();
	return smoothedPoints
	

func set_gesture():
	# Now only extracts points, rest is handled in worker thread 
	if get_node("Line").get_child_count() > 0:
		var children = get_node("Line").get_children()
		for i in range(children.size()):
			pointsArray = append_vec3_array(children[i], i)

		


func append_vec3_array(line, index):
	var points : Array = []
	if pointsArray != null:
		points = pointsArray
	for point in line.points:
		var vec3 : Vector3 = Vector3(point.x, point.y, index)
		points.append(vec3)
	return points

func resize_points(points):
	var newPoints : Array[Vector3]
	newPoints.resize(steps)
	newPoints[0] = points[0]
	var numPoints : int = 1
	
	var length : float = 0
	
	for i : int in range(1, points.size()):
		if points[i].z == points[i-1].z:
			length += distance(points[i-1], points[i])
	
	var lengthStep = length / (steps -1)
	
	var dist : float
	var sumDist : float
	for i in range(1, points.size()):
		if points[i - 1].z == points[i].z and numPoints < steps - 1:
			dist = distance(points[i - 1], points[i])
			
			if (dist + sumDist) > lengthStep:
				var lastPoint = points[i - 1]
				while (dist + sumDist) > lengthStep:
					var prom = (lengthStep - sumDist) / dist
					prom = clamp(prom, 0, 1)
					if is_nan(prom):
						prom = 0.5
					var newPoint = Vector3((1.0 - prom) * lastPoint.x + prom * points[i].x, (1.0 - prom) * lastPoint.y + prom * points[i].y, points[i].z)
					#newPoints[numPoints] = points[i]
					
					dist = dist + sumDist - lengthStep
					sumDist = 0
					
					newPoints[numPoints] = newPoint
					numPoints += 1
				sumDist = dist
			else:
				sumDist += dist
	if numPoints == steps - 1:
		newPoints[numPoints] = Vector3(points.back().x, points.back().y, points.back().z)
	
	pointsArray = newPoints
	pointsDissapear = pointsArray
	pass

func normalize_points(points):
	# Normalización de Puntos
	var minx = INF
	var maxx = -INF
	var miny = INF
	var maxy = -INF

	for point in points:
		if point.x < minx:
			minx = point.x
		if point.x > maxx:
			maxx = point.x
		if point.y < miny:
			miny = point.y
		if point.y > maxy:
			maxy = point.y

	var normalizedPoints = []
	var scalex = 1.0 / (maxx - minx)
	var scaley = 1.0 / (maxy - miny)

	for point in points:
		var normx = (point.x - minx) * scalex
		var normy = (point.y - miny) * scaley
		normalizedPoints.append(Vector3(normx, normy, point.z))
	
	for point in normalizedPoints:
		if is_nan(point.x) or is_nan(point.y):
			reset_gesture()
			reset_gesture_data()
			error = true
			return

	pointsNorm = normalizedPoints
	gestureResource.points = normalizedPoints
	#return normalizedPoints

func integers_points(points):
	pointsIntegers.resize(points.size())
	for i in range(points.size()):
		var px = int((points[i].x + 1.0) / 2.0 * (maxCoords - 1))
		var py = int((points[i].y + 1.0) / 2.0 * (maxCoords - 1))
		var pz = points[i].z
		pointsIntegers[i] = Vector3(px, py, pz)
	gestureResource.pointsInt = pointsIntegers
	pass

func LUT_construct():
	
	for i in LUTSize:
		for j in LUTSize:
			var minDist : int = INF
			var index : int = -1
			for k : int in range(pointsIntegers.size()):
				var fila : int = pointsIntegers[k].y / LUTScale
				var col : int = pointsIntegers[k].x / LUTScale
				var dist : int = pow((fila-i),2) + pow((col-j), 2)
				if dist < minDist:
					minDist = dist
					index = k
			LUT[Vector2(i, j)] = index
	gestureResource.LUT = LUT
	pass

func reset_gesture():
	line_disappear.emit(pointsDissapear)
	
	for childs in get_node("Line").get_children():
		childs.queue_free()
	if Outline:
		for childs in get_node("Outline").get_children():
			childs.queue_free()
	

func reset_gesture_data():
	if pointsArray != null:
		pointsArray.clear()
	if pointsNorm != null:
		pointsNorm.clear()
	if pointsIntegers != null:
		pointsIntegers.clear()
	if LUT != null:
		LUT.clear()
	

func distance(ubi1, ubi2):
	var dist : float;
	dist = Vector2(ubi1.x, ubi1.y).distance_to(Vector2(ubi2.x, ubi2.y))
	return dist
	pass

func isDrawing() -> bool:
	if onDrawing:
		return true
	else:
		return false
	return false
