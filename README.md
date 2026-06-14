# DelphiHookUtils

![Version](https://img.shields.io/badge/version-v1.0-yellow.svg)
![License](https://img.shields.io/github/license/delphilite/DelphiHookUtils)
![Lang](https://img.shields.io/github/languages/top/delphilite/DelphiHookUtils.svg)
![stars](https://img.shields.io/github/stars/delphilite/DelphiHookUtils.svg)

[English](./README.md) | [Chinese](./README.zh-CN.md)

DelphiHookUtils is a Delphi/Pascal inline hook library for Windows. It is inspired by wr960204's [delphi-hook-library](https://code.google.com/p/delphi-hook-library) and replaces BeaEngine with [LDE64](https://github.com/BeaEngine/lde64) to keep the compiled code small. The library supports function pointer hooks, Win32 API export hooks, Delphi COM/interface method hooks, and TObject method hooks on x86, x64, and ARM64EC.

## Features

- Inline trampoline hooks for **x86**, **x64**, and **ARM64EC** targets.
- `HookProc` overloads for a direct function pointer or a loaded module export name.
- `HookInterface` for COM and Delphi interface methods by **MethodIndex**.
- `HookProc` on Delphi object method pointers such as `@TObject.FreeInstance`.
- Uses embedded **LDE64** instruction-length decoding instead of BeaEngine, keeping the unit footprint small.
- `UnHookProc` restores the original entry point and frees trampoline memory.
- Includes DUnit tests and demos for VCL, FMX, Delphi console, Free Pascal, IE, XP, RTL, and BPL scenarios.

## Requirements

- Delphi 7 or later, or Free Pascal with `{$MODE DELPHI}`
- Windows x86, x64, or ARM64EC
- Two units in `Source/`: `HookUtils.pas` and `HookIntfs.pas`

## Installation

### Manual

1. Clone this repository.
2. Add the `Source` directory to your Delphi, Lazarus, or Typhon project search path.
3. Add `HookUtils` and/or `HookIntfs` to your unit `uses` clause.

```pascal
uses
  HookUtils, HookIntfs;
```

### Delphinus

This repository includes Delphinus metadata:

- `Delphinus.Info.json`
- `Delphinus.Install.json`

After publishing the repository, it can be indexed by [Delphinus](https://github.com/Memnarch/Delphinus) as a source-only package. Restart the IDE after installing through Delphinus so the new search path is picked up.

## Usage

For more runnable examples, see the projects under `Demos/`.

### Hook a Win32 API Export

```pascal
uses
  Windows, HookUtils;

var
  MessageBoxNext: function (hWnd: HWND; lpText, lpCaption: PChar;
    uType: UINT): Integer; stdcall;

function MessageBoxCallback(hWnd: HWND; lpText, lpCaption: PChar;
  uType: UINT): Integer; stdcall;
begin
  Result := MessageBoxNext(hWnd, 'Hooked text', lpCaption, uType);
end;

procedure InstallApiHook;
begin
  HookProc('user32.dll', 'MessageBoxW', @MessageBoxCallback, @MessageBoxNext);
end;

procedure RemoveApiHook;
begin
  UnHookProc(@MessageBoxNext);
end;
```

`HookProc` with module and export names only works when the target module is already loaded. Call `LoadLibrary` first if needed.

### Hook by Function Pointer

```pascal
var
  TargetNext: Pointer;

procedure InstallPointerHook;
begin
  HookProc(SomeFunction, @ReplacementProc, TargetNext);
end;
```

On x64, trampoline memory must be allocated within ±2 GB of the target entry point. On ARM64EC, native ARM64 and emulated x64 targets are detected automatically.

### Hook a Delphi Interface Method

`HookIntfs` resolves Delphi COM stubs and hooks the underlying method implementation.

```pascal
uses
  ComObj, ShlObj, HookIntfs;

var
  ShellLink: IShellLink;
  SetPathNext: function (Self: IShellLink; pszFile: LPTSTR): HResult; stdcall;

function SetPathCallback(Self: IShellLink; pszFile: LPTSTR): HResult; stdcall;
begin
  Result := SetPathNext(Self, 'C:\Windows');
end;

procedure InstallInterfaceHook;
begin
  ShellLink := CreateComObject(CLSID_ShellLink) as IShellLink;
  HookInterface(ShellLink, 20, @SetPathCallback, @SetPathNext);
end;
```

`AMethodIndex` is the VTable slot index, including methods inherited from parent interfaces. `CalcInterfaceMethodAddr` can be used to inspect the resolved entry point.

### Hook an Object Method

```pascal
var
  FreeInstanceNext: procedure (Self: TObject);

procedure FreeInstanceCallback(Self: TObject);
begin
  FreeInstanceNext(Self);
end;

procedure InstallObjectHook;
begin
  HookProc(@TObject.FreeInstance, @FreeInstanceCallback, @FreeInstanceNext);
end;
```

### Call the Original Function

`HookProc` and `HookInterface` return a trampoline pointer in `AOldProc`. Call it from your replacement procedure to execute the saved prologue and continue into the original body:

```pascal
Result := MessageBoxNext(hWnd, lpText, lpCaption, uType);
```

`UnHookInterface` is equivalent to `UnHookProc` for interface hooks.

## Error Handling

`HookProc` and `HookInterface` return `False` when the target is invalid, memory cannot be allocated, page protection cannot be changed, or LDE64 cannot decode the entry instructions. They do not raise exceptions for those failures. Wrap installation and removal in normal Delphi `try/finally` blocks and always unhook during unit `finalization` or application shutdown.

## Notes

- Source files are kept as UTF-8 with Windows CRLF line endings.
- Install and remove hooks from unit `initialization`/`finalization` or controlled startup/shutdown code. The library does not suspend other threads while patching code.
- Do not hook functions whose entry is smaller than 5 bytes on x86/x64, or smaller than 16 bytes on native ARM64.
- Do not hook targets whose first overwritten bytes contain branch or jump instructions.
- Delphi BPL exports and DLL import thunks are resolved through an internal `FixFunc` pass on x86/x64.
- On ARM64EC, native ARM64 code uses absolute `LDR/BR` trampolines allocated with EC-marked memory; emulated x64 targets keep the x64 long-jump path.
- For design details, platform differences, and review notes, see [Doc/Hook.md](./Doc/Hook.md) and [Doc/Arm64.md](./Doc/Arm64.md).

## Contributing

Contributions are welcome! Please fork this repository and submit pull requests with your improvements. Behavior changes should include matching DUnit coverage in `UnitTest/`.

## License

This project is licensed under the Mozilla Public License 2.0. See [LICENSE](./LICENSE) for details.

## Acknowledgements

Thanks to wr960204 for the original [delphi-hook-library](https://code.google.com/p/delphi-hook-library) design and to the [LDE64](https://github.com/BeaEngine/lde64) project for the lightweight instruction-length engine used in this library.
