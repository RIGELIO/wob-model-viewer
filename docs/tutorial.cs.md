# WoB Model Viewer krok za krokem

[English tutorial](tutorial.en.md) · [Stáhnout Viewer](https://github.com/RIGELIO/wob-model-viewer/releases/latest) · [Přehled funkcí](../README.cs.md)

1. [Spuštění a otevření modelu](#spuštění-a-otevření-modelu)
2. [Kamera, scéna a vrstvy](#kamera-scéna-a-vrstvy)
3. [Informace o objektu](#informace-o-objektu)
4. [Kontrola geometrie a materiálů](#kontrola-geometrie-a-materiálů)
5. [Osvětlení, uložení a snímky](#osvětlení-uložení-a-snímky)
6. [Přehrávání a kontrola animace](#přehrávání-a-kontrola-animace)
7. [Terminál v aplikaci](#terminál-v-aplikaci)
8. [Příkazová řádka a automatizace](#příkazová-řádka-a-automatizace)
9. [Export pro 3D tisk](#export-pro-3d-tisk)

## Spuštění a otevření modelu

1. Ve Windows rozbal ZIP s názvem `windows-portable` a spusť **WoB Model Viewer.exe**. Alternativou je **Windows Setup**.
2. V Linuxu rozbal ZIP s názvem `linux-portable` a spusť `./wob-model-viewer`. Pokud rozbalovací nástroj nepřenese oprávnění, nejprve použij `chmod +x wob-model-viewer wob-gif`. Na Debianu a Ubuntu můžeš použít také balíček DEB.
3. Přetáhni model do okna nebo použij **Soubor → Otevřít** či **Ctrl+O**. Viewer otevře GLB, glTF, FBX, OBJ, STL, relace `.wobview` a manifesty vozů Wars of Bohemia. U glTF ponech odkazované soubory `.bin` a textury na relativních cestách z exportu.
4. Jazyk přepni v nabídce **Okno**. **Nápověda → Průvodce krok za krokem** otevře interaktivní průvodce přímo v aplikaci. **F1** otevře ovládání a **Ctrl+L** protokol.

Když je po otevření povrch bílý, projdi **Materiály a diagnostika**. Viewer zkouší názvy textur u modelu a nejvýše dvě úrovně nad ním. Chybějící mapy můžeš doplnit přes **Načíst textury…**. Herní textury a shadery lze přiřadit také z místní kolekce `_materialy-z-hry` s indexem a složkou `assets`.

## Kamera, scéna a vrstvy

- Tažením levým tlačítkem otáčíš kolem modelu. Pravé nebo prostřední tlačítko posouvá pohled. Kolečkem měníš přiblížení.
- **F** zarámuje objekt a kliknutí na stěnu orientační kostky nastaví směr kamery. **F11** přepne celou obrazovku. V horní liště pohledu jde zvolit perspektivu nebo pravoúhlou projekci.
- Vlevo rozbal objekt a pak skupinu sítí. Zaškrtávátko u vrstvy ovládá její viditelnost. Skupina materiálů obsahuje povrchy a jejich sloty. Strom dále nabízí kostru a klipy, pokud je obsahuje načtený soubor.
- Zobrazení panelů ovládá nabídka **Okno**. Při automatickém skrytí lze panel znovu zobrazit u příslušného okraje.

## Informace o objektu

Vpravo nahoře otevři **ⓘ** vedle osvětlení. Označení ve stromu scény určuje rozsah údajů.

| Co označit | Co uvidíš |
| --- | --- |
| Kořen s názvem souboru | Cestu, formát, velikost v bajtech, čas změny v UTC, rozměry, počty sítí, povrchů, vrcholů a trojúhelníků, souhrn atributů, LOD, počty koster a klipů a diagnostiku. U glTF také dostupného exportéra, rozšíření a doplňková metadata. |
| Jednotlivou síť | Cestu uzlu, viditelnost vrstvy, místní rozměry, transformaci, vazby na kosti, názvy morph targetů a geometrii po površích. |
| Materiálový slot | Typ primitivy, vrcholy, indexy, trojúhelníky a atributy povrchu, aktivní materiál, případný shader, hodnoty PBR a velikosti dostupných map. |
| Kostru nebo klip | Názvy a počty kostí nebo délku klipu, dráhy animace a počty klíčů. |

**Zkopírovat údaje** přenese zobrazený výpis do schránky. **Obnovit údaje** pořídí nový výpis aktuálního výběru, například po změně polohy v animaci. Počet vrcholů vychází z importované geometrie po površích. Švy UV a hranice materiálů mohou mít samostatné vrcholy. Rozměry celého objektu vycházejí z obálky při importu.

### Export do JSON a CSV

1. V záložce **ⓘ** klikni ve stromu na kořen pro celý model nebo na jednotlivou síť pro jednu vrstvu.
2. Stiskni **Export JSON** nebo **Export CSV** a vyber cílový soubor. Stejně lze exportovat výpis materiálu, kostry nebo animace, pokud je ve stromu vybraná.
3. JSON používá verzi schématu, rozsah `scope`, cestu `source_path` a údaje v `details`. Počty jsou čísla a rozměry jsou pole hodnot X, Y a Z v metrech. České a anglické rozhraní používají stejné klíče. Text diagnostiky používá jazyk rozhraní.
4. CSV je v UTF-8 a má dva sloupce `field,value`. Například `/details/geometry/triangle_count` odpovídá počtu trojúhelníků. Tabulkový editor při importu nastav na oddělovač čárku. Pokud text připomíná vzorec, CSV ho označí apostrofem, aby zůstal textem. Pro nezměněnou hodnotu použij JSON.

## Kontrola geometrie a materiálů

1. **W** přepne wireframe trojúhelníků. **Q** zapne odhad quadů, který spojuje sousední trojúhelníky. Výsledek je odhad původní topologie. **P** přepne zobrazení vrcholů jako bodů.
2. V inspektoru zobrazení vyber **Vertex barvy** a sadu, například `COLOR_0`. Přepnutím na kanál R, G, B nebo A zkontroluješ samotnou masku. Režimy UV zobrazí šachovnici první nebo druhé sady souřadnic.
3. V záložce **Materiál** vyber slot. U editovatelných materiálů lze v náhledu upravit barvu, drsnost, kovovost a normálovou mapu. Změnu náhledu můžeš uložit do relace. Produkční materiály a zdrojové vertex barvy zůstávají v původním souboru.
4. Pro srovnání LOD dej exporty se společným základem názvu, například `postava_lod0.glb` a `postava_lod1.glb`, do stejné složky. V **Model a LOD** porovnej počty a velikosti. **Page Up** a **Page Down** mění LOD při zachování pohledu.

U texturovaného materiálu první změna základní barvy zapne **Plnou barvu**, aby byl odstín vidět i na tmavém albedu. Vypnutím přepínače se vrátí původní albedo a vertex barvy pro tónovaný náhled. Samostatná záložka **Osvětlení** obsahuje světla, HDRI a nastavení oblohy.

## Osvětlení, uložení a snímky

1. V **Osvětlení** vyber vestavěnou předvolbu nebo vlastní panoramatický HDR či EXR v poměru 2:1. Samostatné přepínače ovládají HDRI, přímé světlo a odrazy.
2. **Den · Slunce** a **Noc · Měsíc** zobrazí příslušný zdroj. V režimu **Cyklus dne a noci** můžeš čas posunout ručně nebo spustit plynulý cyklus. Podlahu, mřížku a pozadí zapínáš samostatně.
3. **Soubor → Uložit jako** vytvoří `.wobview` s odkazem na model a nastavením pohledu. Relace zahrnuje kameru, světla, volbu LOD a animaci včetně časového výřezu. Přemístíš-li model, znovu vyber jeho dostupnou kopii. **Ctrl+R** obnoví model po reexportu a zachová nastavení pohledu.
4. **Ctrl+E** vyrenderuje PNG 3840 × 2160. Chceš-li průhledné pozadí, vypni **Zobrazit pozadí** před exportem.

## Přehrávání a kontrola animace

1. Vyber klip dole, přehraj jej mezerníkem a krokovacími tlačítky hledej konkrétní pózu. Nastav rychlost od 0× do 2×. Pro pomalou kontrolu zkus 0,1× nebo 0,01×. **Na místě** potlačí vodorovný posun u rozpoznaného root motion.
2. Zapni **Výřez** a označ začátek a konec na pravítku pod posuvníkem. Úsek lze také vybrat tažením. **Smyčka** opakuje výřez. Po jejím vypnutí se přehrávání zastaví na jeho konci.
3. **Model → Editor pohybu** umožňuje vybírat klouby, zkoušet úpravy a připínat značky ke kostem. **Analyzovat pohyb** hledá problémy s kontaktem chodidel, skoky rotací a návazností při opakování. Výběr nálezu nastaví čas přehrávání.
4. Chceš-li GIF, nastav **Model → Rozsah animace**, FPS a rozlišení a použij **Export animace GIF**. Export používá vlastní interval. Přiložený kodér `wob-gif` nebo `wob-gif.exe` ponech vedle programu.

## Terminál v aplikaci

Otevři **Okno → Terminál prohlížeče** nebo stiskni **Ctrl+T**. Příkazy používají anglické názvy v obou jazycích. Enter spustí příkaz a šipky nahoru a dolů procházejí historii. Cesty a názvy se slovy oddělenými mezerami uzavři do uvozovek. Desetinná čísla zapisuj s tečkou.

```text
help
open "D:\Modely\postava lod0.glb"
info model
clips
clip "Walk Cycle"
speed 0.25
cut 0.4 1.2
play
```

Nahraď cestu a jméno klipu vlastními údaji. Na Linuxu může cesta vypadat například jako `/home/user/modely/postava.glb`. Příkaz `info` vypíše výběr ve stromu a `info model` celý objekt. `cut off` obnoví celý klip, `pause` pozastaví pohyb a `seek 0.6` přejde na konkrétní čas. Mřížku můžeš zapnout přes `grid on`, přepnout drátové zobrazení přes `view wireframe` a uložit pohled přes `screenshot "D:\Modely\kontrola.png"`. Úplný seznam vrátí `help`.

Terminál ovládá aktuální okno Vieweru. Vstup interpretuje jako příkazy aplikace.

Pro export z terminálu zadej například následující příkazy. Přepínač `model` vyexportuje celý objekt bez ohledu na označení ve stromu. `selection` použije aktuální výběr a je výchozí. Příkaz vyžaduje nový název souboru.

```text
export info "D:\Modely\objekt.json" model
export info "D:\Modely\vrstva.csv" selection
```

## Příkazová řádka a automatizace

### Dávkový export údajů bez okna

Ve Windows spusť PowerShell ve složce Vieweru a použij přiložený soubor `WoB Model Viewer.console.exe`. Pokud máš Viewer nainstalovaný, najdeš jej vedle běžného EXE. Uveď cestu ke složce nebo ke konkrétnímu modelu.

```powershell
$viewer = (Resolve-Path ".\WoB Model Viewer.console.exe").Path
& $viewer --headless -- "--export-info=Q:\Hotove-modely" "--output-dir=D:\Exporty\WoB" --format=json
$LASTEXITCODE
```

Pro CSV použij `--format=csv`. Pro jediný model můžeš zadat například `"--export-info=Q:\Hotove-modely\chalupa.glb"`. Viewer prochází zadanou složku bez podsložek a zpracuje GLB, glTF, FBX, OBJ a STL. Pokud cílová složka chybí, vytvoří ji. Vznikne jeden soubor na model, například `chalupa.glb.json`. Přípona modelu zůstává v názvu, aby se stejně pojmenované GLB a FBX nepřepsaly.

Existující výstupy Viewer ponechá, pokud výslovně nepřidáš `--overwrite`. Po chybě jednoho modelu pokračuje dalšími. Poslední řádek začíná `WOB_VIEWER_INFO_RESULT` a obsahuje souhrn JSON s výsledkem každého souboru. Návratový kód `0` znamená kompletní export, `1` neúplný export a `2` chybu zadání nebo cílové složky.

Pro jeden společný přehled ze složky a všech podsložek použij `--recursive` a `--summary-csv`.

```powershell
& $viewer --headless -- "--export-info=Q:\Hotove-modely" --recursive "--summary-csv=D:\Exporty\prehled.csv"
```

Přehled má jeden řádek na soubor a sloupce `path`, `triangles` a `status`. U chyby načtení je počet prázdný a stav `load_failed`. Pro samostatné reporty vedle souhrnu přidej `--output-dir`. Reporty se pak ukládají ve stejné struktuře podsložek jako modely. Při rekurzi se vynechávají odkazy na adresáře.

```sh
./wob-model-viewer --headless -- "--export-info=/home/user/modely" "--output-dir=/home/user/export" --format=csv
```

### Otevření modelu a snímky

Pro jedno spuštění použij systémový terminál. Volba `--` odděluje parametry Vieweru. Snímek vyžaduje grafické prostředí. Po uložení se instance zavře s návratovým kódem.

```powershell
& ".\WoB Model Viewer.exe" -- "D:\Modely\postava.glb" "--language=cs"
& ".\WoB Model Viewer.exe" -- "D:\Modely\postava.glb" "--screenshot=D:\Modely\kontrola.png"
```

```sh
./wob-model-viewer -- "/home/user/modely/postava.glb" --language=cs
./wob-model-viewer -- "/home/user/modely/postava.glb" "--screenshot=/home/user/kontrola.png"
```

Pro dávkovou analýzu ulož úlohu jako `analyza.json` vedle modelu. Relativní cesty v úloze se vztahují ke složce tohoto JSONu. `start` a `finish` jsou časy v sekundách. Zvol název klipu z vlastního modelu a interval, který se do klipu vejde.

```json
{
  "version": 1,
  "type": "analyze",
  "model": "postava.glb",
  "clip": "Walk Cycle",
  "start": 0.4,
  "finish": 1.2,
  "fps": 30,
  "result": "vysledek.json"
}
```

```sh
./wob-model-viewer --headless -- --viewer-job=analyza.json
```

Ve Windows použij `& ".\WoB Model Viewer.exe" --headless -- --viewer-job=analyza.json`. Ve skriptu můžeš číst `vysledek.json` v obou systémech. Pro GIF použij `"type": "gif"` a doplň `"output": "vyrez.gif", "width": 640, "height": 360`. GIF vyžaduje grafické prostředí, takže jej spusť bez `--headless`. Analýza podporuje 5–60 FPS a nejvýše 900 vzorků. GIF podporuje 5–30 FPS, nejvýše 240 snímků a rozlišení do 1280 × 720.

## Export pro 3D tisk

1. Otevři model. Pro konkrétní pózu vyber klip a posuň se na požadovaný čas. Při otevření exportu se přehrávání pozastaví.
2. Vyber **Soubor → Exportovat pro 3D tisk…** a zvol **Aktuální snímek animace** nebo **Základní pózu**. Export používá viditelné díly a respektuje izolaci.
3. Nastav měřítko a vyber **STL**, **3MF** nebo **OBJ**. Při 100 % odpovídá jeden metr ve Vieweru 1000 mm ve výstupu. Geometrie má osu Z nahoru a její nejnižší bod leží na Z = 0.
4. Otevři soubor ve sliceru a zkontroluj rozměry, orientaci a případné otevřené hrany. Export ukládá geometrii jedné pózy. Materiály, animace a povrchy generované až shaderem se do tiskové sítě nezapisují.

Viewer otevře také binární i textové STL a Wavefront OBJ. Textury z jednoduchého MTL ulož na původních relativních cestách. U STL předpokládá milimetry. Běžné OBJ otevírá v osách modelu a s jednotkou 1 m, vlastní tiskové OBJ rozpozná pomocí hlavičky a při otevření převádí zpět z milimetrů.
