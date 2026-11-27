extends AcceptDialog

const LESSONS := [
	[
		"Otevření prvního modelu",
		"Přetáhni GLB, glTF nebo FBX do okna, případně zvol Soubor → Otevřít. Přiložené textury a soubory BIN nech ve složkách, které model očekává.\n\nPo načtení najdeš vpravo počet vrcholů, trojúhelníků a rozměry. Pokud má model více LOD, přepínej je v části Model a LOD.",
	],
	[
		"Kamera a zobrazení",
		"Levé tlačítko otáčí kamerou kolem modelu, pravé nebo prostřední posouvá pohled a kolečko přibližuje. V nabídce Pohled vyber Zarámovat, Zepředu, Z boku nebo Shora.\n\nVpravo v části Zobrazení zapni mřížku, podlahu, kostru nebo osy modelu. Přepni na Wireframe, vertex barvy nebo UV šachovnici a prohlédni si geometrii. Skrytý panel obnovíš tlačítkem u okraje.",
	],
	[
		"Materiály a světlo",
		"Vpravo v části Osvětlení vyber panorama HDRI nebo načti vlastní. Nastav světlo a odrazy samostatně a vyzkoušej denní, noční nebo cyklickou oblohu.\n\nV části Díly a materiály vyber síť či povrch a zapni izolaci. Pokud se materiál nenačetl, klikni na upozornění ve stavovém řádku. Zobrazí se protokol s podrobnostmi.",
	],
	[
		"Přehrávání a rozbor pohybu",
		"Vyber klip vpravo v části Přehrávání animace. Přehrávej, krokuj nebo přepínej smyčku v horní nabídce Animace. Rychlost uprav vpravo, čas zvol na spodní časové ose.\n\nPro animaci s kostrou otevři Model → Analyzovat pohyb. Kliknutím na nález přejdeš na jeho čas. Pro smyčku jen v části klipu zapni Výřez a označ dvě hranice na pravítku pod posuvníkem. Rozsah exportu a vzorkování nastav v Model → Rozsah animace.",
	],
	[
		"Úpravy pohybu a nová kostra",
		"Pro animovanou kostru otevři Model → Editor pohybu. Klikni na kost v pohledu a použij ovládání v pravém panelu k úpravě rotace snímku, přichycení končetiny nebo kreslení značky.\n\nPro model bez kostry zvol Model → Navrhnout novou kostru. Vpravo vyber šablonu nebo Přidat kloub. Kliknutím ho umísti a tažením dolaď.",
	],
	[
		"Uložení práce a export",
		"Soubor → Uložit jako uloží relaci pohledu do souboru .wobview. Z nabídky Soubor vytvoř i snímek 4K.\n\nV nabídce Model můžeš uložit report s úpravami nebo vyexportovat GIF. Před GIFem nastav časový výřez, FPS a rozlišení v nabídce Rozsah animace. Návrh kostry se ukládá v pravém panelu jako .wobrig nebo exportuje do nového GLB.",
	],
]

var _lesson := 0
var _picker: OptionButton
var _instructions: RichTextLabel
var _back: Button
var _next: Button


func _ready() -> void:
	exclusive = true
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_show_lesson)
	column.add_child(_picker)

	_instructions = RichTextLabel.new()
	_instructions.custom_minimum_size = Vector2(0, 204)
	_instructions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instructions.selection_enabled = true
	column.add_child(_instructions)

	var navigation := HBoxContainer.new()
	column.add_child(navigation)
	_back = Button.new()
	_back.text = "Předchozí krok"
	_back.pressed.connect(func(): _show_lesson(_lesson - 1))
	navigation.add_child(_back)
	_next = Button.new()
	_next.text = "Další krok"
	_next.pressed.connect(func(): _show_lesson(_lesson + 1))
	navigation.add_child(_next)


func open_guide() -> void:
	title = tr("Průvodce krok za krokem")
	get_ok_button().text = tr("Zavřít")
	_picker.clear()
	for index in LESSONS.size():
		_picker.add_item("%d/%d  ·  %s" % [index + 1, LESSONS.size(), tr(LESSONS[index][0])])
	_show_lesson(_lesson)
	var window_size := get_parent().get_window().size
	popup_centered(Vector2i(clampi(window_size.x - 48, 260, 660), 360))


func _show_lesson(index: int) -> void:
	_lesson = clampi(index, 0, LESSONS.size() - 1)
	_picker.select(_lesson)
	_instructions.text = tr(LESSONS[_lesson][1])
	_instructions.scroll_to_line(0)
	_back.disabled = _lesson == 0
	_next.disabled = _lesson == LESSONS.size() - 1
