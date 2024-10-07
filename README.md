# DelphiHookUtils

![Version](https://img.shields.io/badge/version-v1.0-yellow.svg)
![License](https://img.shields.io/github/license/delphilite/DelphiHookUtils)
![Lang](https://img.shields.io/github/languages/top/delphilite/DelphiHookUtils.svg)

DelphiHookUtils is a utility library for code hooking, inspired by wr960204's [delphi-hook-library](https://code.google.com/p/delphi-hook-library). This library replaces BeaEngine with [LDE64](https://github.com/BeaEngine/lde64) to reduce size, along with additional modifications and improvements.

## Features
* Support **x86** and **x64** architecture.
* Support hooking interfaces methods by **MethodIndex**.
* Support hooking Object Method.
* Support Delphi 7-12 x86/x64 for Win.
* Support Lazarus/FPC x86/x64 for Win.

## Installation
To install the DelphiHookUtils binding, follow these steps:

1. Clone the repository:
    ```sh
    git clone https://github.com/delphilite/DelphiHookUtils.git
    ```

2. Add the DelphiHookUtils\Source directory to the project or IDE's search path.

## Usage
For more examples, refer to the ones under the Demos folder in the library.

## Documentation
For more information, refer to the wiki documentation below.

1. [Windows API Hooking Techniques](https://en.wikipedia.org/wiki/Hooking) - General overview of hooking methods in software.
2. [Microsoft Detours](https://github.com/microsoft/Detours/wiki) - Microsoft's library for intercepting Win32 functions.
3. [MahdiSafsafi DDetours](https://github.com/MahdiSafsafi/DDetours/wiki) - MahdiSafsafi's library for intercepting Win32 functions.

## Contributing
Contributions are welcome! Please fork this repository and submit pull requests with your improvements.

## License
This project is licensed under the Mozilla Public License 2.0. See the [LICENSE](LICENSE) file for details.
