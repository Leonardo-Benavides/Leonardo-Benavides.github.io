# Plantilla Base de Web Flasher (ESP32 & ESP32-S3)

Plantilla genérica y modular para crear y publicar páginas web de instalación/flasheo de firmware para microcontroladores **ESP32** y **ESP32-S3** utilizando [ESP Web Tools](https://esphome.github.io/esp-web-tools/) y la Web Serial API.

---

## 🚀 Características

* **Detección Automática por Hardware**: La página web detecta automáticamente la familia del chip (`ESP32` o `ESP32-S3`) conectada por USB y flashea el binario correspondiente sin requerir intervención manual.
* **Selector Manual Reactivo**: Permite al usuario forzar la instalación para una arquitectura específica (`Auto`, `ESP32-S3` o `ESP32`) actualizando dinámicamente el manifiesto y las instrucciones en pantalla.
* **Flujo Multi-Proyecto por Ramas (Branches)**: Cada proyecto de firmware puede vivir en su propia rama de Git (ej: `sensor_web`, `medidor_web`) dentro del mismo repositorio de GitHub Pages (`Leonardo-Benavides.github.io`).
* **Inicializador Guiado (`init_web.sh`)**: Escanea proyectos ESP-IDF en directorios hermanos, personaliza nombres, arranca en versión `v0.1` y crea la rama de Git correspondiente.
* **Release y Versionado Estandarizado (`release.sh`)**: Automatiza la sincronización de binarios, incrementos semánticos de versión (`0.1 -> 0.2`), Conventional Commits, tags de Git y push al remoto.

---

## 🛠️ Cómo Utilizar esta Plantilla para un Nuevo Proyecto

### 1. Inicialización de un nuevo proyecto
Ejecuta el script interactivo de setup:
```bash
./init_web.sh
```
El script te guiará en los siguientes pasos:
1. **Selección del proyecto de firmware**: Escaneará la carpeta superior `..` y te mostrará una lista numerada de tus proyectos ESP-IDF (o te permitirá introducir una ruta personalizada).
2. **Nombre visible y Versión**: Define el nombre del proyecto en la web y la versión inicial (por defecto `v0.1`).
3. **Rama Git**: Creará y conmutará automáticamente a una nueva rama de Git aislada (ej: `<proyecto>_web`).
4. **Limpieza**: Te preguntará si deseas eliminar `init_web.sh` para dejar la rama limpia.

---

### 2. Flasheo y Publicación de Releases
Cada vez que compiles una nueva versión de tu firmware en tu proyecto ESP-IDF (`idf.py build`):
```bash
./release.sh
```
El script:
1. Leerá la ruta de compilación desde `.web_config`.
2. Detectará los binarios generados (`merged-binary-esp32s3.bin`, `merged-binary-esp32.bin`).
3. Te sugerirá la siguiente versión calculada (`0.1 -> 0.2`).
4. Te permitirá elegir el tipo de Conventional Commit (`feat`, `fix`, `docs`, etc.).
5. Actualizará de forma atómica `manifest.json`, `manifest-esp32s3.json`, `manifest-esp32.json` e `index.html`.
6. Creará el commit, tag `vX.Y` y subirá los cambios a la rama activa de tu repositorio GitHub.

---

## 📂 Estructura del Repositorio

```text
├── index.html                  # Interfaz web con selector de microcontrolador y ESP Web Tools
├── manifest.json               # Manifiesto principal (Modo Automático: ESP32 + ESP32-S3)
├── manifest-esp32s3.json       # Manifiesto filtrado para ESP32-S3
├── manifest-esp32.json         # Manifiesto filtrado para ESP32 estándar
├── merged-binary-esp32s3.bin   # Binario para ESP32-S3
├── merged-binary-esp32.bin     # Binario para ESP32
├── init_web.sh                 # Script interactivo de vinculación y setup inicial
├── release.sh                  # Script estandarizado de versionado y release
└── README.md                   # Documentación de uso
```
