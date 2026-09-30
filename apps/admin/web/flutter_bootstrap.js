{{flutter_js}}
{{flutter_build_config}}

// GPU CanvasKit (chromium). Raster CPU bikin seluruh admin terasa berat.
// CPU hanya jika WebGL tidak ada.
function _obosTanpaGpu() {
  try {
    const c = document.createElement("canvas");
    return !(c.getContext("webgl2") || c.getContext("webgl"));
  } catch (e) {
    return true;
  }
}

_flutter.loader.load({
  config: {
    renderer: "canvaskit",
    canvasKitVariant: "chromium",
    canvasKitForceCpuOnly: _obosTanpaGpu(),
  },
});
