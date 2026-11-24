extends RefCounted

const MAGIC := 0x46546C67
const JSON_CHUNK := 0x4E4F534A

var bytes: PackedByteArray
var json: Dictionary
var json_end: int
var error := ""


func _init(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = tr("Soubor nelze přečíst (%s).") % error_string(FileAccess.get_open_error())
		return
	var size := file.get_length()
	var text_format := path.get_extension().to_lower() == "gltf"
	if size < (2 if text_format else 20) or size > 0x7fffffff:
		error = tr("Velikost souboru je mimo podporovaný rozsah glTF.")
		return
	bytes = file.get_buffer(size)
	if bytes.size() != size:
		error = tr("Soubor se nepodařilo dočíst.")
		return
	var json_data := bytes if text_format else _binary_json(size)
	if not error.is_empty():
		return
	if text_format and json_data.size() >= 3 and json_data[0] == 0xEF and json_data[1] == 0xBB and json_data[2] == 0xBF:
		json_data = json_data.slice(3)
	var parser := JSON.new()
	if parser.parse(json_data.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		error = tr("Neplatný JSON modelu.")
		return
	json = parser.data
	for group in ["buffers", "images"]:
		var entries: Variant = json.get(group, [])
		if not entries is Array:
			error = tr("Neplatný seznam %s v GLB.") % group
			return
		for entry: Variant in entries:
			if not entry is Dictionary:
				error = tr("Neplatný záznam %s v GLB.") % group
				return
			var uri := str(entry.get("uri", ""))
			if not uri.is_empty() and not uri.begins_with("data:") and not relative_file(uri):
				error = tr("glTF odkazuje mimo složku modelu. Vlož zdroj do modelu nebo použij relativní cestu.")
				return


func _binary_json(size: int) -> PackedByteArray:
	if bytes.size() != size or bytes.decode_u32(0) != MAGIC or bytes.decode_u32(4) != 2 \
			or bytes.decode_u32(8) != size or bytes.decode_u32(16) != JSON_CHUNK:
		error = tr("Soubor nemá platnou hlavičku GLB 2.0.")
		return PackedByteArray()
	var json_size := bytes.decode_u32(12)
	json_end = 20 + json_size
	if json_size < 2 or json_size % 4 != 0 or json_end > size:
		error = tr("Soubor má neplatný JSON blok GLB.")
		return PackedByteArray()
	var cursor := json_end
	while cursor < size:
		if size - cursor < 8:
			error = tr("Neúplná hlavička bloku GLB.")
			return PackedByteArray()
		var chunk_size := bytes.decode_u32(cursor)
		if chunk_size % 4 != 0 or chunk_size > size - cursor - 8:
			error = tr("Neplatná délka datového bloku GLB.")
			return PackedByteArray()
		cursor += 8 + chunk_size
	return bytes.slice(20, json_end)


static func relative_file(uri: String) -> bool:
	if uri.to_lower().contains("%00"):
		return false
	var normalized := uri.uri_decode().replace("\\", "/")
	return not normalized.begins_with("/") and not ":" in normalized \
		and not ".." in normalized.split("/")


func with_json(replacement: Dictionary) -> PackedByteArray:
	# Change only the engine-facing semantic reference. Keep the source JSON and binary intact.
	var json_data := JSON.stringify(replacement, "", false, true).to_utf8_buffer()
	if json_end == 0:
		return json_data
	while json_data.size() % 4 != 0:
		json_data.append(0x20)
	var result := bytes.slice(0, 20)
	result.encode_u32(8, 20 + json_data.size() + bytes.size() - json_end)
	result.encode_u32(12, json_data.size())
	result.append_array(json_data)
	result.append_array(bytes.slice(json_end))
	return result
