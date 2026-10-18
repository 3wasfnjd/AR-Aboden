shader_type spatial;
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

// Opaque sea for Quest 3 (README: "نسخة معتمة بلون عمق مخبوز").
#define WATER_OPAQUE
#include "res://island/water.gdshaderinc"
