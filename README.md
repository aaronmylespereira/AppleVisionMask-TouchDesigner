# Apple Vision Mask for TouchDesigner

A high-performance C++ TOP plugin for TouchDesigner that utilizes Apple's native Vision framework (`VNGeneratePersonSegmentationRequest`) to perform real-time person segmentation and background removal. This plugin is designed for macOS, specifically leveraging Apple Silicon for hardware-accelerated inference.

## Features

*   **Real-time Person Segmentation:** Uses Apple's Vision framework for robust detection.
*   **Adjustable Quality:** Choose between 'Accurate', 'Balanced', or 'Fast' modes to trade off between precision and performance.
*   **Output Modes:**
    *   **Composited:** Returns the subject as a white silhouette against a transparent background.
    *   **Mask Only:** Returns the alpha mask directly.
*   **Opacity Control:** Adjust the transparency of the generated mask.

## Requirements

*   **Operating System:** macOS (optimized for Apple Silicon / arm64).
*   **Software:** TouchDesigner (Commercial or Pro / Non-Commercial might work if C++ TOPs are supported in your version, usually they are).
*   **Hardware:** Apple Silicon (M1/M2/M3) recommended for best performance.

## Building the Plugin

1.  Open a terminal and navigate to the project root directory.
2.  Create a build directory:
    ```bash
    mkdir build
    cd build
    ```
3.  Generate the build files using CMake:
    ```bash
    cmake ..
    ```
4.  Compile the plugin:
    ```bash
    make
    ```
5.  The resulting `AppleVisionMask.plugin` will be created in the `build` directory (or `build/AppleVisionMask.plugin/Contents/MacOS/` depending on CMake setup, but usually the `.plugin` bundle is the artifact).

## Installation & Unquarantining

Since this is a custom unsigned plugin, macOS will likely quarantine it, preventing it from loading in TouchDesigner. You **must** remove the quarantine attribute before use.

1.  Locate the `AppleVisionMask.plugin` file (either downloaded or built).
2.  Open Terminal.
3.  Run the following command, adjusting the path to where your plugin is located:

    ```bash
    sudo xattr -d com.apple.quarantine /path/to/AppleVisionMask.plugin
    ```
    
    *Example:* If you are in the build folder:
    ```bash
    sudo xattr -d com.apple.quarantine AppleVisionMask.plugin
    ```

4.  **To use in TouchDesigner:**
    *   **Option A (Custom Operator):** Place the `AppleVisionMask.plugin` into your standard TouchDesigner Plugins folder (e.g., `~/Documents/TouchDesigner/Plugins`). Restart TouchDesigner. It should appear in the TOPs dialog under the "Custom" tab (or as "Apple Vision Mask").
    *   **Option B (CPlusPlus TOP):** Create a **CPlusPlus TOP** in your project. In the "Plugin Path" parameter, browse and select the `AppleVisionMask.plugin` file.

## Example

An example TouchDesigner project file is included to demonstrate usage:

*   **File:** `Examples/AppleMask.toe`
*   **Usage:** Open this file in TouchDesigner. It is pre-configured to look for the plugin (you may need to re-link the "Plugin Path" on the CPlusPlus TOP if it's not found).

## Parameters

*   **Opacity:** Controls the alpha transparency of the output.
*   **Output Mode:**
    *   *Composited:* Outputs a white cutout.
    *   *Mask Only:* Outputs just the alpha channel (useful for masking other textures).
*   **Quality:**
    *   *Accurate:* Best edge detection, higher GPU/Neural Engine usage.
    *   *Balanced:* Good trade-off (Default).
    *   *Fast:* Lowest latency, slightly rougher edges.

## License

MIT License so use as needed