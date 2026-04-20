// Render LaTeX equations to self-contained SVGs using MathJax.
// GitHub mobile renders images but not $$...$$ — every equation in README.md
// is pre-rendered here and referenced as <img>.
//
// Usage:
//   npm install --prefix . mathjax-full
//   node render-math.js

const fs = require("fs");
const path = require("path");

const MJ_PATH = path.join(__dirname, "node_modules", "mathjax-full");
require(path.join(MJ_PATH, "js", "util", "asyncLoad", "node.js"));

const { mathjax } = require(path.join(MJ_PATH, "js", "mathjax.js"));
const { TeX } = require(path.join(MJ_PATH, "js", "input", "tex.js"));
const { SVG } = require(path.join(MJ_PATH, "js", "output", "svg.js"));
const { liteAdaptor } = require(path.join(MJ_PATH, "js", "adaptors", "liteAdaptor.js"));
const { RegisterHTMLHandler } = require(path.join(MJ_PATH, "js", "handlers", "html.js"));
const { AllPackages } = require(path.join(MJ_PATH, "js", "input", "tex", "AllPackages.js"));

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);

const tex = new TeX({ packages: AllPackages });
const svg = new SVG({ fontCache: "none" });
const html = mathjax.document("", { InputJax: tex, OutputJax: svg });

const FG = "#e6edf3";
const OUT = path.join(__dirname, "math");
fs.mkdirSync(OUT, { recursive: true });

// Labels follow root README ordering (H1=Semantic Diff, H2=Bayesian Trust,
// H3=Info-Gain, H4=Continuity, H5=Adversarial, H6=Gauss Learning).
// H4 + H5 are structural (graph assembly, question dispatch) and have
// no closed-form formula.
const EQUATIONS = [
  ["h1-classify",
   String.raw`\mathrm{classify}(f) = \begin{cases} \mathrm{config} & f \in \{\texttt{.json},\,\texttt{.yaml},\,\texttt{.env}\} \\ \mathrm{test} & f \in \{\texttt{test},\,\texttt{spec}\} \\ \mathrm{schema} & f \in \{\texttt{.sql},\,\texttt{migration}\} \\ \mathrm{source} & \text{otherwise} \end{cases}`],
  ["h2-bayes",
   String.raw`P(\theta \mid D) = \dfrac{P(D \mid \theta)\,P(\theta)}{P(D)} \qquad P(\theta) = \mathrm{Beta}(\alpha,\,\beta)`],
  ["h2-update",
   String.raw`\alpha_{\mathrm{new}} = \alpha + \ell \qquad \beta_{\mathrm{new}} = \beta + (1 - \ell) \qquad \mathrm{trust} = \dfrac{\alpha}{\alpha + \beta}`],
  ["h3-infogain",
   String.raw`IG(X) = H(X) = -p \log_2 p \;-\; (1 - p) \log_2(1 - p)`],
  ["h6-gauss",
   String.raw`r_{\mathrm{new}} = \alpha \cdot s_{\mathrm{current}} + (1 - \alpha) \cdot r_{\mathrm{prior}} \qquad \alpha = 0.3`],
];

function render(name, source) {
  const node = html.convert(source, { display: true, em: 16, ex: 8, containerWidth: 1200 });
  let svgStr = adaptor.innerHTML(node);
  svgStr = svgStr.replace(/currentColor/g, FG);
  svgStr = `<?xml version="1.0" encoding="UTF-8"?>\n` + svgStr;
  fs.writeFileSync(path.join(OUT, `${name}.svg`), svgStr, "utf8");
  console.log(`  docs/assets/math/${name}.svg`);
}

console.log(`Rendering ${EQUATIONS.length} equations...`);
for (const [name, src] of EQUATIONS) {
  try { render(name, src); } catch (err) {
    console.error(`FAILED: ${name}\n  ${err.message}`);
    process.exitCode = 1;
  }
}
console.log("Done.");
