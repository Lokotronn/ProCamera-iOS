# ProCamera Studio for iOS (Professional AVFoundation Camera Engine)

Aplicación de cámara profesional para iPhone diseñada para fotógrafos avanzados, con control manual absoluto del hardware del sensor a través de **AVFoundation**, análisis de imagen en tiempo real con **Accelerate Framework (vImage)** y **Metal Shaders**, y una interfaz "Dark Studio" inspirada en los controles mecánicos de Leica y Fujifilm.

---

## 🏛 Arquitectura del Proyecto

El proyecto sigue estrictamente los principios de **Clean Architecture** y **SOLID**:

```text
ProCameraApp/
├── project.yml                          # Especificación XcodeGen (generación limpia del proyecto)
├── .gitignore                           # Exclusiones de build y derivados
├── .github/
│   └── workflows/
│       └── build-ipa.yml                # CI/CD: Pipeline de compilación de .ipa en macOS vía GitHub Actions
└── ProCameraApp/
    ├── App/
    │   ├── AppDelegate.swift            # Ciclo de vida de la aplicación
    │   ├── SceneDelegate.swift          # Configuración de ventana y vista raíz
    │   └── Info.plist                   # Permisos de privacidad del sensor y fototeca
    ├── Core/
    │   ├── Models/
    │   │   ├── CameraSettings.swift     # Enums de ópticas, formatos (ProRAW/DNG), telemetría
    │   │   └── HistogramData.swift      # Estructuras de bins RGB y detección de clipping
    │   ├── Hardware/
    │   │   ├── CameraEngineProtocols.swift # Interfaces desacopladas (ISP / SOLID)
    │   │   └── CameraEngine.swift       # Abstracción de bajo nivel de AVFoundation
    │   └── Processing/
    │       ├── HistogramProcessor.swift # Cálculo SIMD/NEON de histograma con vImage
    │       └── FocusPeakingFilter.swift # Procesamiento de bordes en tiempo real
    └── UI/
        ├── Controllers/
        │   └── CameraViewController.swift # Controlador principal "Dark Studio"
        ├── Views/
        │   ├── CameraPreviewView.swift   # Visor con retícula y regla de tercios
        │   ├── HistogramView.swift       # Vista de histograma RGB con alertas de clipping
        │   ├── DialControlView.swift     # Dial táctil con haptics y marcas mecánicas
        │   └── ExposureReadoutView.swift # Telemetría técnica monoespaciada (Leica/Fuji)
        └── Shaders/
            └── FocusPeakingShaders.metal # Kernel Metal con filtro Sobel para peaking
```

---

## ⚙️ Características Técnicas de Bajo Nivel

1. **AVFoundation Puro**: Cero dependencias de capas de alto nivel como `UIImagePickerController`. Control directo del sensor CMOS vía `AVCaptureDevice` y `AVCaptureSession`.
2. **Triángulo de Exposición Manual**:
   - **Sensibilidad ISO**: Control discreto y continuo mediante `setExposureModeCustom(duration:iso:)`, respetando los límites físicos `minISO` y `maxISO`.
   - **Velocidad de Obturación**: Manipulación precisa de tiempos en fracciones de segundo con `CMTime` (ej. 1/8000s hasta 2.0s).
   - **Bloqueo AEL/AFL**: Modos `.locked` tanto para exposición como para enfoque.
3. **Control Óptico**:
   - Selección dinámica de lentes entre Ultra Gran Angular (`0.5x`), Gran Angular (`1.0x`) y Teleobjetivo (`3.0x`/`5.0x`) con reconfiguración atómica sin parpadeos.
   - Enfoque manual micrométrico mediante `lensPosition` (0.0 macro a 1.0 infinito).
4. **Análisis Digital Profesional**:
   - **Histograma RGB + Luminancia**: Procesamiento en paralelo de los búferes de vídeo `32BGRA` con `vImageHistogramCalculation_ARGB8888` de Apple Accelerate. Detección automática de sobreexposición (altas luces quemadas) y subexposición (sombras empastadas).
   - **Focus Peaking**: Shader Metal con detección de gradientes Sobel $3 \times 3$ resaltando bordes enfocados en verde fluorescente.
   - **Formatos RAW / ProRAW**: Salida de fotogramas directos del sensor en formato DNG de 14 bits / Apple ProRAW (`kCVPixelFormatType_14Bayer_RGGB`).
5. **UI Dark Studio & Háptica**:
   - Fondo negro absoluto `#000000` (evita contaminación luminosa en situaciones de baja luz).
   - Tipografía monoespaciada con feedback físico en cada muesca del dial (`UIImpactFeedbackGenerator`) y respuesta mecánica pesada al accionar el obturador.

---

## 🚀 Compilación del .IPA mediante GitHub Actions (Simulación de Mac)

Dado que compilar binarios iOS requiere macOS y Xcode, este repositorio incluye un flujo automatizado en **GitHub Actions** que ejecuta una máquina virtual macOS (Apple Silicon M-series) en los servidores de GitHub para compilar y empaquetar el `.ipa`.

### Pasos para compilar:

1. **Crear un Repositorio en GitHub**:
   - Ve a [GitHub](https://github.com) y crea un nuevo repositorio (ej. `ProCamera-iOS`).

2. **Subir este código al repositorio**:
   ```bash
   git init
   git add .
   git commit -m "feat: initial pro camera source code"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/ProCamera-iOS.git
   git push -u origin main
   ```

3. **Ejecución Automática del Pipeline**:
   - Al hacer `push`, GitHub Actions detectará `.github/workflows/build-ipa.yml`.
   - Se levantará un entorno `macos-14`, instalará XcodeGen, generará el `.xcodeproj` y ejecutará `xcodebuild archive`.
   - Empaquetará el ejecutable en `Payload/ProCamera.app` y generará `ProCamera.ipa`.

4. **Descargar el archivo .ipa compilado**:
   - En tu repositorio de GitHub, haz clic en la pestaña **Actions**.
   - Selecciona la última ejecución de **"Build iOS ProCamera IPA"**.
   - En la sección **Artifacts** al final de la página, encontrarás el archivo descargable **`ProCamera-Unsigned-IPA`**.

5. **Instalación en el iPhone**:
   - Puedes instalar el `.ipa` en tu iPhone usando:
     - **AltStore / SideStore** (gratis con tu Apple ID).
     - **Sideloadly** (Windows / Mac).
     - **TrollStore** (en versiones de iOS compatibles con CoreTrust).
     - Cuenta de desarrollador Apple vía Xcode o Configurator.
