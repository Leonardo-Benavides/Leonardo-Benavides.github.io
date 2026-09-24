# Plantilla Base de Web Flasher (ESP32-S3)

Plantilla genérica y modular para crear y publicar páginas web de instalación/flasheo de firmware para microcontroladores **ESP32-S3** utilizando [ESP Web Tools](https://esphome.github.io/esp-web-tools/) y la Web Serial API.

---

## 🚀 Características

* **Instalación Directa ESP32-S3**: Flasheo directo y optimizado para la arquitectura **ESP32-S3** (Xtensa LX7) mediante Web Serial API.
* **Interfaz Minimalista y Reactiva**: Página web ligera sin selectores manuales innecesarios, lista para conectar el microcontrolador y flashear.
* **Flujo Multi-Proyecto por Ramas (Branches)**: Cada proyecto de firmware puede vivir en su propia rama de Git (ej: `sensor_web`, `medidor_web`) dentro del mismo repositorio de GitHub Pages (`Leonardo-Benavides.github.io`).
* **Inicializador Guiado (`init_web.sh`)**: Escanea proyectos ESP-IDF en directorios hermanos, personaliza nombres, arranca en versión `v0.1` y crea la rama de Git correspondiente.
* **Release y Versionado Estandarizado (`release.sh`)**: Automatiza la sincronización del binario `merged-binary-esp32s3.bin`, incrementos semánticos de versión (`0.1 -> 0.2`), Conventional Commits, tags de Git y push al remoto.

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
2. Detectará el binario generado (`merged-binary-esp32s3.bin` o `merged-binary.bin`).
3. Te sugerirá la siguiente versión calculada (`0.1 -> 0.2`).
4. Te permitirá elegir el tipo de Conventional Commit (`feat`, `fix`, `docs`, etc.).
5. Actualizará de forma atómica `manifest.json` e `index.html`.
6. Creará el commit, tag `vX.Y` y subirá los cambios a la rama activa de tu repositorio GitHub.

---

## 📂 Estructura del Repositorio

```text
├── index.html                  # Interfaz web optimizada para ESP32-S3 con ESP Web Tools
├── manifest.json               # Manifiesto oficial para ESP32-S3
├── merged-binary-esp32s3.bin   # Binario unificado para ESP32-S3
├── init_web.sh                 # Script interactivo de vinculación y setup inicial
├── release.sh                  # Script estandarizado de versionado y release
└── README.md                   # Documentación de uso
```
