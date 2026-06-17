{ *********************************************************************** }
{                                                                         }
{   Delphi 通用 Hook 库，支持 Windows x86/x64/ARM64EC, Ansi/Unicode       }
{                                                                         }
{   设计：Lsuper 2016.10.01                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2026 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   注意：                                                                }
{                                                                         }
{   1、建议 Hook/Unhook 放到单元初始化、析构中做，否则可能因改写内存没挂  }
{      起其他线程的调用而造成错误                                         }
{   2、ARM64EC：进程同时存在原生 ARM64 与被模拟的 x64 代码，借助          }
{      ntdll!RtlIsEcCode、IsWow64Process2 区分目标架构：                  }
{    - 当 ARM64 主机模拟 x86/x64 进程下的虚表重定向挂接：当系统 COM 方法  }
{      为原生 ARM64 代码时，改写 ARM64 字节会触发非法指令，改为替换虚表槽 }
{      指向 ANewProc，并以跳板保存原始入口。跳板为被模拟的 x86/x64 代码， }
{      其间接 JMP 由模拟器在调用边界完成 x86/x64 ↔ ARM64 架构切换。       }
{    - 原生目标（代码架构相同）：直接 Hook 替换目标方法。                 }
{   3、钩 COM 对象有一个技巧，如果你想在最早时机勾住某个 COM 对象可以在你 }
{      要钩 COM 对象创建前自己先创建一个该对象，Hook 住然后释放你自己的对 }
{      象，这样这个函数已经被下钩子了，而且是钩在这个 COM 对象创建前的    }
{                                                                         }
{   限制：                                                                }
{                                                                         }
{   1、不能 Hook 代码大小小于 5 个字节的函数，不能 Hook 前 5 个字节有跳转 }
{      指令的函数                                                         }
{   2、希望使用的朋友们自己也具有一定的汇编或者逆向知识，Hook 函数前请确  }
{      定该函数不属于上面两种情况                                         }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   2026.06.15 - Lsuper                                                   }
{                                                                         }
{   1、增加 Windows ARM64EC 支持。注意进程中可能同时存在原生 ARM64 代码与 }
{      被模拟的 x64 代码。同架构直接挂钩，跨架构改用 COM 虚表重定向。     }
{                                                                         }
{   2016.10.01 - Lsuper                                                   }
{                                                                         }
{   1、由 HookUtils 中拆分 COM 相关函数至此 HookIntfs 单元                }
{                                                                         }
{ *********************************************************************** }

unit HookIntfs;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$RANGECHECKS OFF}

interface

function HookInterface(var AInterface; AMethodIndex: Integer; ANewProc: Pointer;
  out AOldProc: Pointer): Boolean;
function UnHookInterface(var AOldProc: Pointer): Boolean;

function CalcInterfaceMethodAddr(var AInterface; AMethodIndex: Integer): Pointer;

implementation

uses
  Windows, HookUtils;

type
{$IFNDEF FPC} {$IF CompilerVersion < 23}
  NativeUInt = LongWord;
{$IFEND} {$ENDIF}
  PDWORD = ^LongWord;

  TVTableHook = packed record
    JMP: Word;            // $25FF indirect JMP opcode
{$IFDEF CPUX64}
    RelOffset: Int32;     // RIP-relative displacement (0 -> next qword)
{$ELSE}
    PtrRef: Pointer;      // absolute address of OrigProc (x86 JMP [mem])
{$ENDIF}
    OrigProc: Pointer;    // saved original vtable entry; indirect JMP target
    Magic: UInt64;        // identifies this block as a vtable trampoline
    Slot: PPointer;       // vtable slot address, used by UnHookInterface
  end;
  PVTableHook = ^TVTableHook;

const
  // Distinguishes a vtable trampoline from an inline HookProc trampoline, VHOOKTBL
  cVTableHookMagic: UInt64 = $4C42544B4F4F4856;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：计算 COM 对象中方法的地址
//参数：AMethodIndex 是方法的索引
//注意：AMethodIndex 是接口包含父接口的方法的索引，例如:
//      IA = Interface
//      procedure A(); // 因为 IA 是从 IUnKnow 派生的，IUnKnow 自己有 3 个方法所以 AMethodIndex=3
//      end;
//      IB = Interface(IA)
//      procedure B(); // 因为 IB 是从 IA 派生的，所以 AMethodIndex=4
//      end;
////////////////////////////////////////////////////////////////////////////////
function CalcInterfaceMethodAddr(var AInterface; AMethodIndex: Integer): Pointer;
type
  TBuf = array [0 .. $FF] of Byte;
  PBuf = ^TBuf;
var
  pp: PPointer;
{$IFNDEF CPUARM64}
  buf: PBuf;
{$ENDIF}
begin
  // VTable slot for the requested method
  pp := PPointer(AInterface)^;
  Inc(pp, AMethodIndex);
  Result := pp^;

  // Delphi COM method tables are unusual: the interface is a member of the object, so at
  // call time Self is the address of that interface member, not the object. Delphi COM
  // stubs therefore point at a small thunk that adjusts Self (subtract the member offset)
  // then jumps to the real method.
  //
  // We peek at the first bytes of the method pointer; if it adjusts Self, this is a Delphi
  // COM object and we resolve the underlying method address.
  //
  // The logic below detects and handles Delphi COM objects only; COM from other languages is
  // ignored because normal prologues save the frame or spill arguments, never adjust Self first.

  // Typical Delphi COM stub layout:
  // ADD Self, [-offset of COM field in implementing object]
  // JMP Real method

{$IFDEF CPUX64}
  buf := Result;
  // ADD RCX, -COM field offset; JMP to real method (x64 stdcall)
  if (buf^[0] = $48) and (buf^[1] = $81) and (buf^[2] = $C1) and (buf^[7] = $E9)
  then
    Result := Pointer(NativeInt(@buf[$C]) + PDWORD(@buf^[8])^);
{$ELSEIF Defined(CPUARM64)}
  // ARM64 (incl. ARM64EC native code) uses fixed 4-byte instructions, so the
  // x86/x64 byte-pattern probes above must not run here or they may misfire on
  // ARM64 opcodes and corrupt the resolved address. Delphi COM adjustor thunks
  // are uncommon on ARM64; the raw vtable slot is the method entry, which is the
  // correct result for system/C++ COM objects. Left as a documented extension
  // point should Delphi-implemented ARM64 COM adjustor thunks need resolving.
{$ELSE}
  buf := Result;
  // ADD [ESP+$04], -COM field offset; JMP to real method (stdcall/cdecl)
  if (buf^[0] = $81) and (buf^[1] = $44) and (buf^[2] = $24) and
    (buf^[03] = $04) and (buf^[8] = $E9) then
    Result := Pointer(NativeUInt(@buf[$D]) + PDWORD(@buf^[9])^)
  else
    // ADD EAX, -COM field offset; JMP to real method (register calling convention)
    if (buf^[0] = $05) and (buf^[5] = $E9) then
      Result := Pointer(NativeUInt(@buf[$A]) + PDWORD(@buf^[6])^);
{$IFEND}
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.15
//功能：通过替换虚表槽挂接接口方法（跨架构安全）
//参数：AInterface 接口引用；AMethodIndex 方法索引；ANewProc 替换过程；
//      AOldProc 输出跳板指针（调用即转入原始方法）
//返回：成功 True，失败 False
////////////////////////////////////////////////////////////////////////////////
function HookInterfaceVTable(var AInterface; AMethodIndex: Integer;
  ANewProc: Pointer; out AOldProc: Pointer): Boolean;
var
  slot: PPointer;
  orig: Pointer;
  hook: PVTableHook;
  oldProtect, tmpProtect: DWORD;
begin
  Result := False;

  // Locate the vtable slot for the requested method and capture the original
  slot := PPointer(AInterface)^;
  Inc(slot, AMethodIndex);
  orig := slot^;
  if orig = nil then
    Exit;

  // Trampoline lives in emulated x86/x64 memory: its indirect JMP to the native
  // ARM64 original is interpreted by the emulator, which performs the transition
  hook := VirtualAlloc(nil, SizeOf(TVTableHook), MEM_COMMIT or MEM_RESERVE,
    PAGE_EXECUTE_READWRITE);
  if hook = nil then
    Exit;

  hook^.JMP := $25FF;
{$IFDEF CPUX64}
  hook^.RelOffset := 0;
{$ELSE}
  hook^.PtrRef := @hook^.OrigProc;
{$ENDIF}
  hook^.OrigProc := orig;
  hook^.Magic := cVTableHookMagic;
  hook^.Slot := slot;

  // Redirect the vtable slot to the replacement procedure
  if not VirtualProtect(slot, SizeOf(Pointer), PAGE_READWRITE, oldProtect) then
  begin
    VirtualFree(hook, 0, MEM_RELEASE);
    Exit;
  end;
  slot^ := ANewProc;
  VirtualProtect(slot, SizeOf(Pointer), oldProtect, tmpProtect);

  FlushInstructionCache(GetCurrentProcess, hook, SizeOf(TVTableHook));
  AOldProc := hook;
  Result := True;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.15
//功能：还原虚表重定向挂接
//参数：AHook HookInterfaceVTable 分配的跳板
//返回：成功 True，失败 False
////////////////////////////////////////////////////////////////////////////////
function UnHookInterfaceVTable(var AHook: PVTableHook): Boolean;
var
  oldProtect, tmpProtect: DWORD;
begin
  Result := False;
  if not VirtualProtect(AHook^.Slot, SizeOf(Pointer), PAGE_READWRITE, oldProtect) then
    Exit;
  AHook^.Slot^ := AHook^.OrigProc;
  VirtualProtect(AHook^.Slot, SizeOf(Pointer), oldProtect, tmpProtect);
  VirtualFree(AHook, 0, MEM_RELEASE);
  AHook := nil;
  Result := True;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：挂接 COM/接口对象的方法
//参数：AInterface 接口变量引用；AMethodIndex VTable 方法索引（含父接口方法）；
//      ANewProc 替换过程；AOldProc 输出跳板指针
//返回：成功 True，失败 False
////////////////////////////////////////////////////////////////////////////////
function HookInterface(var AInterface; AMethodIndex: Integer;
  ANewProc: Pointer; out AOldProc: Pointer): Boolean;
  ////////////////////////////////////////////////////////////////////////////////
  //设计：Lsuper 2026.06.15
  //功能：判断当前进程是否为 ARM64 主机上模拟运行的 x86/x64 进程
  //参数：
  //注意：模拟进程中系统 COM 对象方法为原生 ARM64 代码，需走虚表重定向方案。
  //      原生 ARM64EC 进程返回 False（ProcessMachine 为 UNKNOWN），仍用内联挂接。
  ////////////////////////////////////////////////////////////////////////////////
  function IsRunningEmulatedOnArm64: Boolean;
  const
    IMAGE_FILE_MACHINE_ARM64                 = $AA64;  { ARM64 Little-Endian }
  var
    hKernel32: HMODULE;
    pIsWow64Process2: function (hProcess: THandle; pProcessMachine: PWord; pNativeMachine: PWord): BOOL; stdcall;
    nNativeMachine, nProcessMachine: Word;
  begin
    Result := False;
    hKernel32 := GetModuleHandle('kernel32.dll');
    if hKernel32 = 0 then
      Exit;
    @pIsWow64Process2 := GetProcAddress(hKernel32, 'IsWow64Process2');
    if not Assigned(pIsWow64Process2) then
      Exit;
    // IsWow64Process2 is a delayed import; absent before Windows 10 1709
    if not pIsWow64Process2(GetCurrentProcess, @nProcessMachine, @nNativeMachine) then
      Exit;
    // nProcessMachine = IMAGE_FILE_MACHINE_UNKNOWN means the process runs natively.
    // This reliably flags an x86 (WOW) process on ARM64, but an x64 process under
    // ARM64 emulation is not WOW and reports UNKNOWN, so it is detected separately
    // via RtlIsEcCode on the target (see IsTargetArm64Ec).
    Result := (nProcessMachine <> IMAGE_FILE_MACHINE_UNKNOWN) and
      (nNativeMachine = IMAGE_FILE_MACHINE_ARM64);
  end;
  ////////////////////////////////////////////////////////////////////////////////
  //设计：Lsuper 2026.06.15
  //功能：判断目标地址是否为原生 ARM64 (EC) 代码
  //参数：APtr 目标地址
  //注意：借助 ntdll!RtlIsEcCode 查询 EC 位图。x64 模拟进程的 ntdll 导出该函数，
  //      可据此识别系统 COM 的原生 ARM64 方法；x86 进程通常无此导出，返回 False，
  //      由 IsRunningEmulatedOnArm64 兜底识别。
  ////////////////////////////////////////////////////////////////////////////////
  function IsTargetArm64Ec(APtr: Pointer): Boolean;
  var
    hNtdll: HMODULE;
    pIsEcCode: function(Addr: Pointer): Boolean; stdcall;
  begin
    Result := False;
    hNtdll := GetModuleHandle('ntdll.dll');
    if hNtdll = 0 then
      Exit;
    @pIsEcCode := GetProcAddress(hNtdll, 'RtlIsEcCode');
    if not Assigned(pIsEcCode) then
      Exit;
    Result := pIsEcCode(APtr);
  end;
  ////////////////////////////////////////////////////////////////////////////////
  //设计：Lsuper 2026.06.15
  //功能：判断是否需要改用虚表重定向挂接（而非内联补丁）
  //参数：ATarget 目标方法地址
  //注意：仅在 x86/x64 构建中可能为 True——此时跳板为被模拟的 x86/x64 代码，其
  //      间接 JMP 可由模拟器完成跨架构切换。原生 ARM64EC 构建恒为 False，仍走内
  //      联 HookProcArm64。普通 x86/x64 主机上目标非 ARM64，亦恒为 False。
  ////////////////////////////////////////////////////////////////////////////////
  function NeedVTableHook(ATarget: Pointer): Boolean;
  begin
{$IFDEF CPUARM64}
    Result := False;
{$ELSE}
    Result := IsTargetArm64Ec(ATarget) or IsRunningEmulatedOnArm64;
{$ENDIF}
  end;
var
  P: Pointer;
begin
  Result := False;
  if ANewProc = nil then
    Exit;

  // Resolve the concrete method entry, then delegate to HookProc
  P := CalcInterfaceMethodAddr(AInterface, AMethodIndex);

  // On ARM64 hosts an emulated x86/x64 process meets native ARM64 system COM
  // methods. Inline patching would corrupt ARM64 code (illegal instruction at
  // call time), so redirect the vtable slot instead; every cross-architecture
  // transition then happens at an indirect-call boundary the emulator handles.
  // Native x86/x64 (and native ARM64EC) targets keep the inline HookProc path.
  //
  // The architecture decision uses the resolved method entry P (past any Delphi
  // adjustor thunk), while HookInterfaceVTable saves/restores the raw vtable slot
  // value (the thunk itself). This is intentional: the slot value is what must be
  // restored on unhook, and resolving past the thunk gives the more accurate
  // architecture of the code that actually runs. A thunk and its target residing
  // in different-architecture regions is not observed in practice for COM here.
  if NeedVTableHook(P) then
    Result := HookInterfaceVTable(AInterface, AMethodIndex, ANewProc, AOldProc)
  else Result := HookUtils.HookProc(P, ANewProc, AOldProc);
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：解除接口方法钩子
//参数：AOldProc HookInterface 返回的跳板指针（解除后置 nil）
//返回：成功 True，失败 False
////////////////////////////////////////////////////////////////////////////////
function UnHookInterface(var AOldProc: Pointer): Boolean;
begin
  Result := False;
  if AOldProc = nil then
    Exit;

  // Distinguish a vtable trampoline (cross-arch path) from an inline trampoline
  if PVTableHook(AOldProc)^.Magic = cVTableHookMagic then
    Result := UnHookInterfaceVTable(PVTableHook(AOldProc))
  else Result := HookUtils.UnHookProc(AOldProc);
end;

end.
