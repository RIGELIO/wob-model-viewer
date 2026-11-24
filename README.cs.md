# WoB Model Viewer

Offline desktopový prohlížeč GLB a glTF pro kontrolu modelů a materiálů Wars of Bohemia. Používá Godot 4.7.2 Forward+ a obsahuje produkční shadery postav a sdílené atlasy.

## Stažení a spuštění

V [nejnovějším vydání](https://github.com/RIGELIO/wob-model-viewer/releases/latest) najdeš instalační EXE pro **Windows x86-64** a balíček `.deb` pro **Debian a Ubuntu x86-64**. Balíček nainstaluješ ve správci balíčků nebo příkazem `sudo apt install ./wob-model-viewer_1.1.0_amd64.deb`. Pro obě platformy je k dispozici přenosný ZIP. Rozbal ho a spusť **WoB Model Viewer.exe** nebo **wob-model-viewer**. Pokud rozbalovací nástroj odebral příznak spuštění, obnov ho příkazem `chmod +x wob-model-viewer`. Aplikace potřebuje grafický ovladač s podporou Godot Forward+.

Pro otevření dvojklikem vyber ve Windows v **Nastavení → Aplikace → Výchozí aplikace** program **WoB Model Viewer** pro přípony **.glb**, **.gltf** a **.wobview**. Instalátor registruje všechny tři pro tvůj účet. V přenosné verzi spusť přiložený **Register-FileTypes.cmd**. Po přemístění aplikace registraci zopakuj.

Instalátor a EXE pro Windows jsou bez digitálního podpisu. Pokud Windows zobrazí výstrahu SmartScreen, ověř stažený soubor proti `SHA256SUMS.txt` na stránce vydání. Podpis umožní Windows zobrazit ověřeného vydavatele. SmartScreen při prvních staženích zohledňuje i reputaci nového souboru. [Dokumentace Microsoftu](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)

Instalátor před instalací zobrazí podmínky a licenci MIT. Při aktualizaci a odinstalaci vyzve k zavření otevřených oken prohlížeče. Odinstalátor odstraní program, jeho zástupce, registraci a známé soubory nastavení a mezipaměti. Uložené modely, relace a snímky zůstanou na svých místech.

## Manifesty vozů

Otevři `vuz_*_manifest.json` nebo jeden z GLB souborů z téže složky. Prohlížeč přiřadí produkční shader vozu, mapy albeda, normál a ORM a u dlaždicových modelů zachová význam `UV2` a `COLOR_0`. Stav vozu a úroveň detailů lze přepínat vedle sebe v nástrojové liště. `*_atlas.json` popisuje rozložení UV atlasu.

## Ovládání

1. Přetáhni `.glb` nebo `.gltf` do okna nebo jej otevři klávesami **Ctrl+O**. Samostatné soubory `.bin` a textury odkazované z `.gltf` ponech na jejich relativních cestách ve složce modelu. Volič **EN / CS** přepíná jazyk a **F1** otevírá nápovědu k ovládání.
2. **Levé tlačítko myši** otáčí modelem. Pravé nebo prostřední tlačítko posouvá pohled a kolečko mění přiblížení. **F** zarámuje model. Směr pohledu nastavíš tlačítky **Zepředu**, **Z boku**, **Shora** nebo kliknutím na barevné orientační osy. Zapni automatické otáčení pro plynulé obíhání modelu. Přepínač posunu mění posun v rovině pohledu na posun po zemi.
3. **Osvětlení** umožňuje samostatně zapnout HDRI, přímé světlo a odrazy HDRI. Uprav intenzitu a otočení HDRI nebo sílu a směr přímého světla. Použij vestavěné HDRI Lilienstein nebo načti vlastní HDR či EXR v poměru 2 : 1.
4. V panelu **Zobrazení** vyber barvu pozadí nebo panorama. Vypnutím pozadí získáš průhledné PNG. Mřížku, podlahu pro stíny, kostru a ortografický pohled můžeš zapínat samostatně. Vedle produkčních materiálů jsou k dispozici wireframe, režim bez osvětlení, normály, overdraw a **Body**. Velikost bodů mění průměr vykreslených vrcholů v režimu **Body**. **Geometrie** uvádí statistiky sítě a časová osa přehrává vložené klipy.
5. **Soubor → Uložit** nebo **Uložit jako** uloží odkaz na model, kameru, osvětlení, nastavení zobrazení a polohu animace do `.wobview`. Relaci znovu otevři přes **Soubor → Otevřít**. **Ctrl+E** nebo **Uložit 4K PNG** vykreslí aktuální 3D scénu do PNG o rozměrech 3840 × 2160.

Při průhledném pozadí Godot Forward+ vypíná podpovrchový rozptyl světla v kůži.

## Kontrola dílů a atributů

- **Ctrl+R** načte aktuální soubor znovu po exportu. Zachová kameru, světla, HDRI, stav vozu a vybraný LOD. Izolace zůstane zapnutá, pokud díl v novém exportu stále existuje.
- Rozbal **Díly a materiály** a vyber síť nebo jeden z jejích materiálových povrchů. Klikni na **Izolovat** nebo použij dvojklik. **Zobrazit vše** obnoví celý model. Statistika geometrie a LOD dál zahrnuje celý model na vybrané úrovni detailů.
- V **Zobrazení → Vertex barvy** vyber původní vrstvu, například `COLOR_0` nebo `COLOR_1`. Můžeš zobrazit RGB dohromady nebo jednotlivé kanály R, G, B a A ve stupních šedi. **UV0 · šachovnice** a **UV2 · šachovnice** zobrazí první a druhou UV vrstvu (`TEXCOORD_0` a `TEXCOORD_1` v glTF). Pruhy označí plochy, kde vybraný atribut chybí.

## Srovnání LOD

U modelu pojmenovaného například `postava_lod0.glb` prohlížeč vyhledá související soubory ve stejné složce, včetně variant jako `postava_lod1_helma.glb`. Seznam LOD ukazuje počty trojúhelníků a vrcholů ze zdrojové scény GLB a velikost každého souboru. Při přepnutí úrovně zůstane kamera na stejném místě.

**Wireframe** zobrazuje trojúhelníky GLB. Režim **Quady (odhad)** odhaduje čtyřúhelníky spojením sousedních trojúhelníků a skrytím odhadnutých úhlopříček. Odhadované čtyřúhelníky se mohou od původní topologie lišit.

## Klávesové zkratky

| Klávesy | Akce |
| --- | --- |
| **1** nebo **F** · **2** · **3** · **4** | Zarámovat · Zepředu · Z boku · Shora |
| **W** · **Q** · **P** | Wireframe · Odhad čtyřúhelníků · Body |
| **G** · **K** · **A** · **B** · **O** | Mřížka · Kostra · Automatické otáčení · Zobrazení pozadí · Orto |
| **Page Up** · **Page Down** | Předchozí LOD · Další LOD |
| **Mezerník** | Přehrát nebo pozastavit animaci |
| **Ctrl+O** · **Ctrl+S** · **Ctrl+Shift+S** | Otevřít · Uložit relaci · Uložit relaci jako |
| **Ctrl+R** | Znovu načíst model a zachovat pohled |
| **Ctrl+E** · **Ctrl+Q** · **F1** | Exportovat 4K PNG · Ukončit · Nápověda |

## Produkční materiály a diagnostika

Prohlížeč podle názvu modelu a materiálu přiřazuje produkční shadery kůže, očí, oděvu, vlasových karet, mikrovláken vlasů a vousů a StubbleShell. Zdrojové soubory si zachovávají své původní vertex color vrstvy. Shader dostává vrstvu, kterou vyžaduje jeho materiál, včetně odlišných vstupů hustoty pro starší a 4K strniště.

Panel **Materiály a diagnostika** vypisuje chybějící atributy, textury i neznámé mapování shaderu. Kde je to možné, zůstává původní materiál z GLB. KeenFace hlavy bez materiálu a neprůhledná čepice LOD3 z referenční sady v5 se při chybějících produkčních podkladech zobrazí neutrálně a s upozorněním.

Vlastní mapování lze nastavit souborem `nazev-modelu.wob.json` ve stejné složce jako model. Klíče v `surfaces` spojují původní název uzlu a index primitivy od nuly. Příklad a názvy shaderů najdeš v [anglickém návodu](https://github.com/RIGELIO/wob-model-viewer#production-materials-and-diagnostics). Balíček obsahuje manifest původu a SHA-256 produkčních prostředků.

## Příkazová řádka

```sh
./wob-model-viewer -- "/local/postava.glb" "--language=cs"
./wob-model-viewer -- "/local/postava.glb" "--screenshot=/local/postava-4K.png"
```

Ve Windows stejné argumenty přijímá `"WoB Model Viewer.exe"`. Automatické snímání používá desktopový renderer a po uložení PNG aplikaci ukončí.

Vestavěné HDRI [Lilienstein od Poly Haven, CC0](https://polyhaven.com/a/lilienstein). Licenční informace Godotu jsou součástí balíčku.

## Licence

© 2026 RIGELIO Studio. Licence MIT umožňuje používání, úpravy a šíření se zachováním copyrightu a licenčního textu. Podrobnosti jsou v souborech [LICENSE](LICENSE) a [RESOURCE-LICENSES.md](RESOURCE-LICENSES.md). Verzi, copyright a licenci najdeš v aplikaci přes **Nápověda → O programu**.
