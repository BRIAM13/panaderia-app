// Desempaqueta el canal alfa de los clips de la mascota y los compone con
// transparencia REAL sobre lo que haya detrás en el árbol de widgets.
//
// Un MP4 no puede llevar canal alfa, así que cada clip viene "empaquetado":
// un cuadro de 1400x900 donde la mitad izquierda (0..679) es el color y la
// mitad derecha (720..1399) es el alfa en escala de grises. Entre ambas hay
// una banda negra de 40 px para que el submuestreo de croma del H.264 y el
// reescalado de la GPU no mezclen color con alfa en la costura.
//
// El matte se calcula fuera de línea (no es un chroma-key por distancia de
// color en vivo): la bata y el gorro blancos del panadero reflejan la luz
// crema del set y caen justo sobre el color del fondo, así que ningún umbral
// los separa. Ver el pipeline de generación en el README de assets/mascota.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;          // tamaño del área dibujada (cuadro empaquetado)
uniform sampler2D uTextura;  // frame actual del video, vía AnimatedSampler

out vec4 fragColor;

const float kAnchoColor = 680.0 / 1400.0;  // fin de la mitad de color
const float kInicioAlfa = 720.0 / 1400.0;  // inicio de la mitad de alfa

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Todo lo que cae en la banda o en la mitad de alfa no se dibuja: el
  // widget que envuelve al shader recorta a la mitad izquierda, esto es
  // solo una red de seguridad por si el recorte no llegara a aplicarse.
  if (uv.x > kAnchoColor) {
    fragColor = vec4(0.0);
    return;
  }

  vec3 color = texture(uTextura, uv).rgb;
  float alfa = texture(uTextura, vec2(uv.x + kInicioAlfa, uv.y)).r;

  // El lienzo de Flutter espera alfa premultiplicado.
  fragColor = vec4(color * alfa, alfa);
}
