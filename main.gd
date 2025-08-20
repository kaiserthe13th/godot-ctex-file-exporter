# Main.tscn (Root Node: Control)
# Attach this script to the root Control node.

extends Control

@onready var file_dialog: FileDialog = $FileDialog
@onready var save_file_dialog: FileDialog = $SaveFileDialog # FileDialog for saving directory/files
@onready var message_label: Label = $CenterContainer/Panel/VBoxContainer/MessageLabel
@onready var image_preview: TextureRect = $CenterContainer/Panel/VBoxContainer/ImagePreview
@onready var save_png_button: Button = $CenterContainer/Panel/VBoxContainer/SavePNGButton # Button for saving

# Dictionary to hold extracted images: { original_ctex_path: Image_object }
var _extracted_images: Dictionary = {} 

func _ready() -> void:
	# Configure the FileDialog for opening .ctex files
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES # Allows selecting multiple files
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "Select one or more .ctex files"
	file_dialog.add_filter("*.ctex;Godot Compressed Texture")
	file_dialog.add_filter("*.tres,*.res;Godot Resource") # Sometimes ctex are inside .tres/.res
	file_dialog.ok_button_text = "Open"
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	# Connect to files_selected for multiple file selection
	file_dialog.files_selected.connect(_on_files_selected) 

	# Configure the FileDialog for saving .png files (will be set to OPEN_DIR for batch)
	save_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_file_dialog.title = "Select Output Directory for PNGs"
	save_file_dialog.ok_button_text = "Save" # Button text for directory selection
	save_file_dialog.canceled.connect(_on_save_file_dialog_canceled)
	# Connect to dir_selected for directory selection
	save_file_dialog.dir_selected.connect(_on_save_file_dialog_dir_selected)
	
	_clear_status()

func _clear_status() -> void:
	message_label.text = "Click 'Load CTEX' to select files."
	image_preview.texture = null
	image_preview.visible = false
	_extracted_images.clear() # Clear all stored images
	save_png_button.disabled = true # Disable save button until images are loaded

# --- UI Callbacks ---
func _on_load_ctex_button_pressed() -> void:
	_clear_status()
	file_dialog.popup_centered()

func _on_save_png_button_pressed() -> void:
	if not _extracted_images.is_empty():
		# Set file mode to select a directory for batch saving
		save_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR 
		save_file_dialog.current_dir = "" # Clear current directory suggestion
		save_file_dialog.popup_centered_ratio()
	else:
		message_label.text = "Error: No images loaded to save."

# --- FileDialog Callbacks ---
func _on_file_dialog_canceled() -> void:
	message_label.text = "File selection cancelled."

func _on_files_selected(paths: PackedStringArray) -> void:
	message_label.text = "Processing " + str(paths.size()) + " files..."
	_extracted_images.clear() # Clear previous images for new batch
	save_png_button.disabled = true # Disable save button during processing

	var first_image_for_preview: Image = null

	for path in paths:
		var image: Image = extract_image_from_ctex(path)
		if image:
			_extracted_images[path] = image
			if not first_image_for_preview:
				first_image_for_preview = image # Store the first image for preview

	if not _extracted_images.is_empty():
		message_label.text = str(_extracted_images.size()) + " images extracted. Click 'Save PNG As...' to choose export location."
		save_png_button.disabled = false # Enable save button after successful extraction

		# Display the first extracted image in the preview
		if first_image_for_preview:
			image_preview.texture = ImageTexture.create_from_image(first_image_for_preview)
			image_preview.visible = true
	else:
		message_label.text = "Error: No valid CTEX textures found in selected files."


func _on_save_file_dialog_canceled() -> void:
	message_label.text = "Save operation cancelled."

func _on_save_file_dialog_dir_selected(dir_path: String) -> void:
	if _extracted_images.is_empty():
		message_label.text = "Error: No images to save."
		return

	message_label.text = "Saving " + str(_extracted_images.size()) + " PNGs to: " + dir_path + "..."
	save_png_button.disabled = true # Disable save button during actual saving

	var saved_count = 0
	var failed_count = 0

	for ctex_path in _extracted_images.keys():
		var image: Image = _extracted_images[ctex_path]
		var file_name = ctex_path.get_file().get_basename() + ".png"
		var output_path = dir_path.path_join(file_name)

		var error = image.save_png(output_path)
		if error == OK:
			saved_count += 1
		else:
			failed_count += 1
			print("Failed to save " + ctex_path + " to " + output_path + ": " + error_string(error))
	
	_extracted_images.clear() # Clear images after saving
	save_png_button.disabled = false # Re-enable save button
	message_label.text = "Batch conversion complete. Saved: " + str(saved_count) + ", Failed: " + str(failed_count) + "."


# --- Extraction Logic (renamed from convert_ctex_to_png for clarity) ---
func extract_image_from_ctex(ctex_path: String) -> Image:
	var loaded_resource: Resource = load(ctex_path)

	if not loaded_resource:
		message_label.text = "Error: Could not load resource from path: " + ctex_path
		return null

	var texture: Texture2D = null

	# Check if it's already a Texture2D or a PackedScene/Mesh with a texture
	if loaded_resource is Texture2D:
		texture = loaded_resource
	elif loaded_resource is PackedScene:
		# If it's a scene, try to find a TextureRect or Sprite2D inside
		var scene_instance = loaded_resource.instantiate()
		add_child(scene_instance) # Temporarily add to scene to access nodes
		if scene_instance.has_node("TextureRect"): # Assuming a TextureRect exists
			texture = scene_instance.get_node("TextureRect").texture
		elif scene_instance.has_node("Sprite2D"): # Assuming a Sprite2D exists
			texture = scene_instance.get_node("Sprite2D").texture
		scene_instance.queue_free() # Clean up temporary instance
	elif loaded_resource is Mesh:
		# If it's a mesh, it might have a material with a texture
		if loaded_resource.surface_get_material_count() > 0:
			var material = loaded_resource.surface_get_material(0)
			if material is StandardMaterial3D and material.albedo_texture:
				texture = material.albedo_texture
			elif material is ORMMaterial3D and material.albedo_texture:
				texture = material.albedo_texture
	
	if not texture:
		message_label.text = "Error: No Texture2D found or extracted from " + ctex_path
		return null

	var image: Image = texture.get_image()
	if not image:
		message_label.text = "Error: Could not get image from texture: " + ctex_path
		return null
	
	return image # Return the extracted image


# --- Helper function for error messages (optional) ---
func error_string(error_code: int) -> String:
	match error_code:
		OK: return "OK"
		ERR_UNAVAILABLE: return "Unavailable"
		ERR_INVALID_PARAMETER: return "Invalid Parameter"
		ERR_CANT_OPEN: return "Can't Open File"
		ERR_CANT_CREATE: return "Can't Create File"
		ERR_FILE_NOT_FOUND: return "File Not Found"
		ERR_FILE_CANT_READ: return "Can't Read File"
		ERR_FILE_CANT_WRITE: return "Can't Write File"
		ERR_PARSE_ERROR: return "Parse Error"
		ERR_BUG: return "Bug"
		ERR_HELP: return "Help"
		ERR_PRINTER_ON_FIRE: return "Printer On Fire"
		_: return "Unknown Error (" + str(error_code) + ")"

# Scene Setup: Main.tscn (Minimal setup)
# 1. Create a new scene and add a `Control` node as the root.
# 2. Rename the root node to `Main`.
# 3. Attach the GDScript code above to the `Main` node.
# 4. Add the following child nodes to the `Main` node:
#    - `CenterContainer` (to center the UI)
#        - `Panel`
#            - `VBoxContainer`
#                - `Button` (Name: `LoadCTEXButton`, Text: "Load CTEX")
#                    - Connect its `pressed()` signal to `_on_load_ctex_button_pressed()` in the script.
#                - `Button` (Name: `SavePNGButton`, Text: "Save PNG As...")
#                    - Set `Disabled` property to `true` initially.
#                    - Connect its `pressed()` signal to `_on_save_png_button_pressed()` in the script.
#                - `Label` (Name: `MessageLabel`, Text: "...")
#                - `TextureRect` (Name: `ImagePreview`, `Expand Mode`: `Fit Width`, `Stretch Mode`: `Keep Aspect Centered`, `Visible`: `false`)
#    - `FileDialog` (Name: `FileDialog`)
#    - `FileDialog` (Name: `SaveFileDialog`)

# Minimal Scene Structure:
# └─Main (Control) -> Attached Script
#    └─CenterContainer
#       └─Panel
#          └─VBoxContainer
#             ├─LoadCTEXButton (Button)
#             ├─SavePNGButton (Button)
#             ├─MessageLabel (Label)
#             └─ImagePreview (TextureRect)
#    ├─FileDialog
#    └─SaveFileDialog
