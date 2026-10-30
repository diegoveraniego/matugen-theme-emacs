"""Independently check exported sRGB pairs and build a before/after viewer."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "validation.json").read_text())
before = json.loads((ROOT / "test/baseline.json").read_text())


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return sum(weight * (v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
               for weight, v in zip((0.2126, 0.7152, 0.0722), channels))


def contrast(a, b):
    low, high = sorted((luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)


metrics = []
pair_count = 0
for row in data["rows"]:
    faces = {f["name"]: f for f in row["faces"]}
    bg = faces["default"]["bg"]
    # Hidden text and window dividers are intentional decorations, not text.
    decorative = {"org-hide", "solaire-org-hide-face", "vertical-border",
                  "window-divider", "window-divider-first-pixel", "window-divider-last-pixel"}
    pairs = []
    for face in row["faces"]:
        if face["fg"] and face["name"] not in decorative:
            value = contrast(face["fg"], face["bg"] or bg)
            pairs.append(value)
            pair_count += 1
            assert value >= 4.5, (row["palette"], row["style"], face, value)
    assert contrast(row["roles"]["cursor"], bg) >= 3
    metrics.append({"palette": row["palette"], "style": row["style"],
                    "minimum_explicit_text_contrast": min(pairs),
                    "text_pairs_checked": len(pairs)})
(ROOT / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")

page = r'''<!doctype html><html lang="es"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Matugen: antes y después</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4f1eb;color:#262622;font:16px/1.6 system-ui,sans-serif}
main{max-width:1250px;margin:auto;padding:32px 24px}h1{font-size:30px;line-height:1.2}h2{font-size:20px}
label{display:inline-flex;flex-direction:column;margin:12px 18px 18px 0}select{font:inherit;padding:8px;border:1px solid #888;border-radius:5px;background:white}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}.editor{padding:25px;min-height:450px;border-radius:8px;font:17px/1.8 Georgia,serif}
.heading{margin:14px 0 8px}.meta{font:13px/1.5 ui-monospace,monospace}pre{font:14px/1.7 ui-monospace,monospace;padding:10px;white-space:pre-wrap}
.swatches{display:flex;gap:5px;margin:15px 0}.swatches span{flex:1;height:30px;border-radius:4px;border:1px solid #8883}
.mode{padding:5px 10px;font:13px/1.5 system-ui,sans-serif;margin-top:20px}.note{max-width:960px;color:#55554e}
table{width:100%;border-collapse:collapse}td,th{padding:10px;border-bottom:1px solid #cbc8c0;text-align:left}.bad{color:#a02020;font-weight:bold}
@media(max-width:850px){.grid{grid-template-columns:1fr}}
</style><main><p class="meta">MATUGEN 1.1 / COMPARACIÓN LOCAL</p><h1>Una paleta con funciones claras</h1>
<p class="note">Colores y atributos calculados por ambas versiones del paquete. La vista reproduce una selección de faces en HTML; la herencia de faces y las fuentes finales de Emacs requieren comprobar la sesión gráfica.</p>
<label>Paleta<select id="palette"><option value="actual-dark">Paleta oscura capturada</option><option value="synthetic-light">Clara de prueba</option><option value="synthetic-medium">Gris medio: resistencia</option><option value="synthetic-low-accent">Acento oscuro: resistencia</option></select></label>
<label>Antes<select id="before"></select></label><label>Después<select id="after"></select></label>
<div class="grid"><section><h2>Antes: versión 1.0</h2><div class="editor" id="old"></div></section><section><h2>Después: versión 1.1</h2><div class="editor" id="new"></div></section></div>
<h2>Contraste del texto</h2><table><thead><tr><th>Uso</th><th>Antes</th><th>Después</th></tr></thead><tbody id="metrics"></tbody></table>
<p class="note">La selección nueva define foreground y background propios. Al seleccionar, reemplaza temporalmente los colores de sintaxis para garantizar legibilidad. Los casos gris medio y acento oscuro son pruebas sintéticas.</p>
<p><a href="README.md">Documentación y perfiles</a> · <a href="metrics.json">Mediciones independientes</a></p></main><script>
const oldData=__OLD__,newData=__NEW__;
const ids=Object.fromEntries(['palette','before','after','old','new','metrics'].map(id=>[id,document.getElementById(id)]));
for(const [id,profiles] of [['before',['full','accent','background','harmonized','monochrome','neon']],['after',['writing','monochrome','coding','presentation','full','accent','background','harmonized','neon']]]){
 ids[id].innerHTML=profiles.map(p=>`<option>${p}</option>`).join('');
}
ids.before.value='monochrome';ids.after.value='writing';
const syntax=['font-lock-variable-name-face','font-lock-string-face','font-lock-type-face','font-lock-function-name-face','font-lock-keyword-face','font-lock-constant-face'];
function lum(h){return h.slice(1).match(/../g).map(x=>parseInt(x,16)/255).reduce((s,v,i)=>s+[.2126,.7152,.0722][i]*(v<=.04045?v/12.92:((v+.055)/1.055)**2.4),0)}
function ratio(a,b){return (Math.max(lum(a),lum(b))+.05)/(Math.min(lum(a),lum(b))+.05)}
function card(node,row){
 const f=Object.fromEntries(row.faces.map(x=>[x.name,x])),bg=f.default.bg,fg=f.default.fg;
 node.style.background=bg;node.style.color=fg;
 const span=(text,name)=>`<span style="color:${f[name].fg};font-weight:${f[name].weight==='bold'?'bold':'normal'}">${text}</span>`;
 const heading=(text,name)=>`<div class="heading" style="color:${f[name].fg};font-weight:bold;font-size:${f[name].height}em">${text}</div>`;
 node.innerHTML=`<div class="meta" style="color:${f['org-meta-line'].fg}">#+title: Cuaderno de escritura</div>${heading('Una idea que necesita espacio','org-level-1')}<p>Escribir también consiste en dejar que el texto respire. La interfaz puede acompañar sin reclamar toda la atención.</p>${heading('Notas para mañana','org-level-2')}<p>Una lista breve, una palabra <span style="background:${f['org-code'].bg};color:${f['org-code'].fg}">importante</span> y tiempo para pensar.</p><pre style="background:${f['org-block'].bg}">${span('(defun','font-lock-keyword-face')} ${span('escribir','font-lock-function-name-face')} (${span('idea','font-lock-variable-name-face')})
  ${span('; una nota al margen','font-lock-comment-face')}
  (message ${span('"Una frase clara"','font-lock-string-face')})</pre><div class="swatches">${syntax.map(n=>`<span style="background:${f[n].fg}" title="${n}: ${f[n].fg}"></span>`).join('')}</div><div style="background:${f.region.bg}">${syntax.map(n=>`<span style="color:${f.region.fg||f[n].fg}">selección </span>`).join('')}</div><div class="mode" style="background:${f['mode-line'].bg};color:${f['mode-line'].fg}">cuaderno.org · ${row.style}</div>`;
 return [ratio(fg,bg),Math.min(...syntax.map(n=>ratio(f[n].fg,bg))),f.region.fg?ratio(f.region.fg,f.region.bg):Math.min(...syntax.map(n=>ratio(f[n].fg,f.region.bg))),Math.min(...syntax.map(n=>ratio(f[n].fg,f['org-block'].bg))),ratio(f['vertico-current'].fg,f['vertico-current'].bg)];
}
function render(){
 const a=card(ids.old,oldData.rows.find(r=>r.palette===ids.palette.value&&r.style===ids.before.value));
 const b=card(ids.new,newData.rows.find(r=>r.palette===ids.palette.value&&r.style===ids.after.value));
 ids.metrics.innerHTML=['Texto principal','Sintaxis sobre fondo principal','Texto seleccionado','Sintaxis sobre bloque Org','Selección en Vertico'].map((label,i)=>`<tr><td>${label}</td><td class="${a[i]<4.5?'bad':''}">${a[i].toFixed(2)}:1</td><td class="${b[i]<4.5?'bad':''}">${b[i].toFixed(2)}:1</td></tr>`).join('');
}
for(const id of ['palette','before','after'])ids[id].addEventListener('change',render);render();
</script></html>'''
page = page.replace("__OLD__", json.dumps(before)).replace("__NEW__", json.dumps(data))
(ROOT / "palette-comparison.html").write_text(page)
print(f"PASS: {pair_count} text pairs across {len(metrics)} combinations; preview generated")
