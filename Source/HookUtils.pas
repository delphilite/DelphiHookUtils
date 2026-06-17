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
{      ntdll!RtlIsEcCode 区分目标架构：                                   }
{    - 原生 ARM64 目标：采用 LDR X16/BR X16 绝对跳转，跳板内存须经        }
{      VirtualAlloc2 携带 MEM_EXTENDED_PARAMETER_EC_CODE 标记为 EC 代码   }
{    - x64 目标（系统 DLL 导出等）：沿用 64 位长跳转方案                  }
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
{      被模拟的 x64 代码。对 x64 目标仍采用 64 位长跳转方案，对原生 ARM64 }
{      目标则使用绝对跳转。                                               }
{                                                                         }
{   2016.10.01 - Lsuper                                                   }
{                                                                         }
{   1、参考 wr960204 武稀松 的原始实现：                                  }
{      https://code.google.com/p/delphi-hook-library                      }
{   2、修改 BeaEngine 引擎为 LDE64 长度反编译引擎，大幅降低大小           }
{      https://github.com/BeaEngine/lde64                                 }
{      http://www.beaengine.org/download/LDE64-x86.zip                    }
{      http://www.beaengine.org/download/LDE64-x64.rar                    }
{   3、去除原始实现对多线程冻结的处理，通常建议 Hook/Unhook 放到单元      }
{      初始化、析构中做，否则可能因改写内存没挂起其他线程造成错误         }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   2012.02.01 - wr960204 武稀松，http://www.raysoftware.cn               }
{                                                                         }
{   1、使用了开源的 BeaEngine 反汇编引擎，BeaEngine 的好处是可以用 BCB 编 }
{      译成 OMF 格式的 Obj，直接链接进 dcu 或目标文件中，无须额外的 DLL   }
{   2、BeaEngine 引擎：                                                   }
{      https://github.com/BeaEngine/beaengine                             }
{      http://beatrix2004.free.fr/BeaEngine/index1.php                    }
{      http://www.beaengine.org/                                          }
{                                                                         }
{ *********************************************************************** }

unit HookUtils;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$RANGECHECKS OFF}

interface

function HookProc(ATargetProc, ANewProc: Pointer;
  out AOldProc: Pointer): Boolean; overload;
function HookProc(const ATargetModule, ATargetProc: string; ANewProc: Pointer;
  out AOldProc: Pointer): Boolean; overload;
function UnHookProc(var AOldProc: Pointer): Boolean;

implementation

{$IF Defined(CPUX64) or Defined(CPUARM64)}
  {$DEFINE CPU_64BIT}
{$IFEND}

{$IFDEF CPU_64BIT}
  {$DEFINE USELONGJMP}
{$ENDIF}

{.$DEFINE USEINT3} { Insert INT3 breakpoint into hook stub for debugging }

uses
  Windows;

const
  // Trampoline saved-prologue buffer size. Worst-case overwrite is 4 bytes plus a
  // single 15-byte instruction = 19 bytes (CalcHookProcSize stops at the first
  // instruction boundary >= SizeOf(TNewProc)). The x64 trampoline then appends a
  // TJMPCode (14 bytes) at that offset, needing 19 + 14 = 33 bytes; 48 leaves margin
  // and keeps the previous behaviour for every realistic prologue.
  conBackCodeSize       = $30;

  // Trampoline page size. Defaults to 4 KiB and is corrected to the real OS page
  // size at unit initialization (see InitPageSize) rather than assuming 4 KiB.
  conSysPageSize        = 4096;

type
{$IFNDEF FPC} {$IF CompilerVersion < 23}
  NativeUInt = LongWord;
{$IFEND} {$ENDIF}

  TJMPCode = packed record
{$IFDEF USELONGJMP}
    JMP: Word;          // $25FF  JMP QWORD PTR [RIP+disp32]
    JmpOffset: Int32;
    Addr: NativeUInt;   // Absolute target for indirect long jump (x64)
{$ELSE}
    JMP: Byte;          // $E9  Near relative JMP
    Addr: NativeUInt;   // 32-bit signed offset from the next instruction
{$ENDIF}
  end;
  PJMPCode = ^TJMPCode;

  TOldProc = packed record
{$IFDEF USEINT3}
    Int3OrNop: Byte;    // $CC INT3 or $90 NOP before backup when USEINT3 is defined
{$ENDIF}
    BackCode: array[0..conBackCodeSize - 1] of Byte; // Saved prologue from the hooked function
    JmpRealFunc: TJMPCode;   // Jump back to original body after prologue
    JmpHookFunc: TJMPCode;   // Jump to the replacement (hook) function

    BackUpCodeSize: Integer; // Bytes overwritten at the target entry
    OldFuncAddr: Pointer;    // Original function entry (for UnHookProc)
  end;
  POldProc = ^TOldProc;

  TNewProc = packed record
    JMP: Byte;          // $E9  Near relative JMP patched at target entry
    Addr: Integer;      // Offset to JmpHookFunc inside the trampoline page
  end;
  PNewProc = ^TNewProc;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：引入 LDE64 长度反编译引擎 ShellCode
//参数：无（编译期嵌入的二进制机器码）
////////////////////////////////////////////////////////////////////////////////
const
{$IFDEF CPU_64BIT}
  {$I 'HookUtils.64.inc'} { from LDE64-x64.rar\LDE64x64.bin }
{$ELSE}
  {$I 'HookUtils.32.inc'} { from LDE64-x86.rar\LDE64-x86\LDE64.bin }
{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：LDE64 长度反编译引擎函数定义
//参数：lpData 指令起始地址；arch 架构标识（0=x86，64=x64）
//注意：x64 下需要处理 DEP 问题
////////////////////////////////////////////////////////////////////////////////
function LDE(lpData: Pointer; arch: LongWord): NativeUInt;
var
  D: Pointer;
  F: LongWord;
  M: TMemoryBasicInformation;
  P: function (lpData: Pointer; arch: LongWord): NativeUInt; stdcall;
begin
  D := @defLde64ShellCode;
  // Ensure embedded shellcode page is executable under DEP (x64)
  if VirtualQuery(D, M, SizeOf(M)) <> 0 then
    if M.Protect <> PAGE_EXECUTE_WRITECOPY then
      VirtualProtect(D, SizeOf(defLde64ShellCode), PAGE_EXECUTE_WRITECOPY, @F);
  P := D;
  Result := P(lpData, arch);
end;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：计算需要覆盖的机器指令大小，借助了 LDE64 反汇编引擎以免指令被从中间切开
//参数：AFunc 目标函数入口地址
//返回：覆盖字节数（至少 SizeOf(TNewProc)），AFunc=nil 时返回 0
////////////////////////////////////////////////////////////////////////////////
function CalcHookProcSize(AFunc: Pointer): Integer;
const
  lde_archi_32          = 0;
  lde_archi_64          = 64;
{$IFDEF CPU_64BIT}
  lde_archi_default     = lde_archi_64;
{$ELSE}
  lde_archi_default     = lde_archi_32;
{$ENDIF}
var
  nLen: LongInt;
  pCode: PByte;
begin
  Result := 0;
  if AFunc = nil then
    Exit;
  pCode := AFunc;
  // Accumulate full instruction lengths until the hook stub fits
  while Result < SizeOf(TNewProc) do
  begin
    nLen := LDE(pCode, lde_archi_default);
    // LDE returns 0 for unrecognized instructions; treat as unhooked target
    if nLen <= 0 then
    begin
      Result := -1;
      Exit;
    end;
    Inc(pCode, nLen);
    Inc(Result, nLen);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：在目标地址 ±2 GB 范围内分配可执行内存
//参数：APtr 参考地址；ASize 申请大小
//返回：成功返回分配地址，失败返回 nil
//注意：32/64 位相对 JMP 偏移为 32 位有符号整数，跳板必须在 ±2 GB 内
////////////////////////////////////////////////////////////////////////////////
function TryAllocMem(APtr: Pointer; ASize: LongWord): Pointer;
const
{$IFDEF CPU_64BIT}
  defAllocationType     = MEM_COMMIT or MEM_RESERVE or MEM_TOP_DOWN;
{$ELSE}
  defAllocationType     = MEM_COMMIT or MEM_RESERVE;
{$ENDIF}
  GB: Int64 = 1024 * 1024 * 1024;
var
  mInfo: TMemoryBasicInformation;
  nMin, nMax: Int64;
  nGranularity: LongWord;
  pbAlloc: Pointer;
  sInfo: TSystemInfo;
begin
  Result := nil;

  GetSystemInfo(sInfo);
  // Scan only within ±2 GB of the hook target
  if NativeUInt(APtr) <= 2 * GB then
    nMin := 1
  else nMin := NativeUInt(APtr) - 2 * GB;
  nMax := NativeUInt(APtr) + 2 * GB;

  pbAlloc := Pointer(nMin);
  while NativeUInt(pbAlloc) < nMax do
  begin
    if (VirtualQuery(pbAlloc, mInfo, SizeOf(mInfo)) = 0) then
      Break;
    nGranularity := sInfo.dwAllocationGranularity;
    // Prefer a free region large enough for the trampoline page
    if ((mInfo.State or MEM_FREE) = MEM_FREE) and (mInfo.RegionSize >= ASize) and (mInfo.RegionSize >= nGranularity) then
    begin
      pbAlloc := PByte(NativeUInt((NativeUInt(pbAlloc) + (nGranularity - 1)) div nGranularity) * nGranularity);
      Result := VirtualAlloc(pbAlloc, ASize, defAllocationType, PAGE_EXECUTE_READWRITE);
      if Result <> nil then
        Break;
    end;
    pbAlloc := Pointer(NativeUInt(mInfo.BaseAddress) + mInfo.RegionSize);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：按模块名与导出名挂接 API
//参数：ATargetModule 模块名；ATargetProc 导出函数名；ANewProc 替换过程；
//      AOldProc 输出跳板指针（调用原函数前导指令）
//注意：如果 ATargetModule 没有被 LoadLibrary 下 Hook 会失败，建议先手工 Load
////////////////////////////////////////////////////////////////////////////////
function HookProc(const ATargetModule, ATargetProc: string; ANewProc: Pointer;
  out AOldProc: Pointer): Boolean;
var
  nHandle: NativeUInt;
  pProc: Pointer;
begin
  Result := False;
  nHandle := GetModuleHandle(PChar(ATargetModule));
  if nHandle = 0 then
    Exit;
  pProc := GetProcAddress(nHandle, PChar(ATargetProc));
  if pProc = nil then
    Exit;
  Result := HookProc(pProc, ANewProc, AOldProc);
end;

{$IFDEF CPUARM64}

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.07
//功能：挂接原生 ARM64 (EC) 函数
//参数：ATargetProc：被替换函数；ANewProc：新函数；AOldProc：备份跳板
//注意：ARM64 指令定长 4 字节，备份固定 cBackCodeSize(16) 字节即可容纳绝对跳转。
//      跳板内存须为 EC 代码页（AllocArm64Mem），否则原生 ARM64 指令会被当作
//      x64 模拟执行而崩溃。备份布局复用 TOldProc，使 UnHookProc 可统一处理：
//        BackCode[0..15]   原函数前 16 字节
//        BackCode[16..31]  绝对跳转回 ATargetProc + 16
////////////////////////////////////////////////////////////////////////////////
function HookProcArm64(ATargetProc, ANewProc: Pointer; out AOldProc: Pointer): Boolean;
  ////////////////////////////////////////////////////////////////////////////////
  //设计：Lsuper 2026.06.07
  //功能：分配标记为原生 ARM64 代码的可执行内存（EC 位图置位）
  //参数：ASize 申请大小
  //注意：普通 VirtualAlloc 分配的页面默认被视为 x64 代码，原生 ARM64 指令置于其中
  //      会被模拟器误当作 x64 执行而崩溃。必须通过 VirtualAlloc2 携带
  //      MEM_EXTENDED_PARAMETER_EC_CODE 标志分配，才会被识别为 ARM64 代码
  ////////////////////////////////////////////////////////////////////////////////
  function AllocArm64Mem(ASize: SIZE_T): Pointer;
  const
    // MEM_EXTENDED_PARAMETER_EC_CODE
    cMemEcCode            = $40;
    // Marks the page as native ARM64 code in the EC bitmap
    // MemExtendedParameterAttributeFlags
    cMemAttrFlags         = 5;
  var
    par: MEM_EXTENDED_PARAMETER;
  begin
    FillChar(par, SizeOf(par), 0);
    par.TypeAndReserved := cMemAttrFlags;
    par.ULong64 := cMemEcCode;
    Result := VirtualAlloc2(0, nil, ASize, MEM_COMMIT or MEM_RESERVE,
      PAGE_EXECUTE_READWRITE, @par, 1);
  end;
  ////////////////////////////////////////////////////////////////////////////
  //设计：Lsuper 2026.06.17
  //功能：判断一条 ARM64 指令是否为 PC 相对编码
  //参数：AInstr 4 字节定长指令
  //注意：备份的前导指令会被搬到跳板另一地址执行，PC 相对指令（ADR/ADRP、
  //      B/BL/B.cond、CBZ/CBNZ、TBZ/TBNZ、LDR/LDRSW literal）的立即数是相对
  //      原 PC 编码的，搬移后基址改变又未做重定位，语义即被破坏。命中则拒绝挂钩。
  ////////////////////////////////////////////////////////////////////////////
  function IsArm64PcRelInstr(AInstr: Cardinal): Boolean;
  begin
    Result :=
      // ADR / ADRP
      ((AInstr and $1F000000) = $10000000) or
      // B (unconditional branch)
      ((AInstr and $FC000000) = $14000000) or
      // BL (branch with link)
      ((AInstr and $FC000000) = $94000000) or
      // B.cond (conditional branch)
      ((AInstr and $FF000010) = $54000000) or
      // CBZ / CBNZ
      ((AInstr and $7E000000) = $34000000) or
      // TBZ / TBNZ
      ((AInstr and $7E000000) = $36000000) or
      // LDR / LDRSW (literal, incl. SIMD&FP literal)
      ((AInstr and $3B000000) = $18000000);
  end;
type
  // ARM64 absolute jump: LDR X16, #8 ; BR X16 ; <8-byte target>, 16 bytes total
  TArm64AbsJmp = packed record
    Ldr: Cardinal;      // $58000050  LDR X16, [PC, #8]
    Br: Cardinal;       // $D61F0200  BR X16
    Addr: UInt64;
  end;
  PArm64AbsJmp = ^TArm64AbsJmp;
const
  cArm64LdrX16          = $58000050;
  cArm64BrX16           = $D61F0200;
  // Fixed 4-byte ARM64 instructions; absolute jump occupies the first 16 bytes
  cBackCodeSize         = SizeOf(TArm64AbsJmp);
var
  oldProc: POldProc;
  jmpBack, jmpTarget: PArm64AbsJmp;
  oldProtected, newProtected: DWORD;
  prologue: PCardinal;
  i: Integer;
begin
  Result := False;

  // The first 16 bytes (4 instructions) are relocated to the trampoline and
  // executed from there. Refuse to hook if any of them is PC-relative, as
  // moving such an instruction without fixing its immediate corrupts the target.
  prologue := PCardinal(ATargetProc);
  for i := 0 to (cBackCodeSize div SizeOf(Cardinal)) - 1 do
    if IsArm64PcRelInstr(PCardinal(NativeUInt(prologue) + NativeUInt(i) * SizeOf(Cardinal))^) then
      Exit;

  AOldProc := AllocArm64Mem(conSysPageSize);
  if AOldProc = nil then
    Exit;

  oldProc := POldProc(AOldProc);
  FillChar(oldProc^, SizeOf(TOldProc), 0);
  oldProc^.BackUpCodeSize := cBackCodeSize;
  oldProc^.OldFuncAddr := ATargetProc;

  // Save the first 16 bytes of the target, then append an absolute jump back.
  // AOldProc is the trampoline entry (@BackCode[0]); calling it runs the
  // Original prologue and then resumes the target at ATargetProc + 16.
  Move(ATargetProc^, oldProc^.BackCode[0], cBackCodeSize);
  jmpBack := PArm64AbsJmp(@oldProc^.BackCode[cBackCodeSize]);
  jmpBack^.Ldr := cArm64LdrX16;
  jmpBack^.Br := cArm64BrX16;
  jmpBack^.Addr := UInt64(ATargetProc) + cBackCodeSize;

  // Patch the target entry to jump to the hook function
  if not VirtualProtect(ATargetProc, cBackCodeSize, PAGE_EXECUTE_READWRITE, oldProtected) then
  begin
    VirtualFree(AOldProc, 0, MEM_RELEASE);
    AOldProc := nil;
    Exit;
  end;

  jmpTarget := PArm64AbsJmp(ATargetProc);
  jmpTarget^.Ldr := cArm64LdrX16;
  jmpTarget^.Br := cArm64BrX16;
  jmpTarget^.Addr := UInt64(ANewProc);

  if not VirtualProtect(ATargetProc, cBackCodeSize, oldProtected, newProtected) then
  begin
    // Restoring the original protection failed, but the hook is already written
    // and functional. Continue with cache flush so the patch takes effect.
    newProtected := oldProtected;
  end;
  // Flush instruction cache so patched code is not executed from stale lines
  FlushInstructionCache(GetCurrentProcess(), ATargetProc, cBackCodeSize);
  FlushInstructionCache(GetCurrentProcess(), oldProc, conSysPageSize);
  Result := True;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.07
//功能：判断指定地址是否为原生 ARM64 (EC) 代码
//参数：APtr 目标地址
//注意：ARM64EC 进程中系统 DLL 导出多为被模拟的 x64 代码，原生 Delphi 代码为
//      ARM64。借助 ntdll!RtlIsEcCode 查询 EC 位图区分二者
////////////////////////////////////////////////////////////////////////////////
function IsTargetArm64(APtr: Pointer): Boolean;
var
  hNtdll: HMODULE;
  pIsEcCode: function (Addr: Pointer): Boolean; stdcall;
begin
  Result := False;
  hNtdll := GetModuleHandle('ntdll.dll');
  if hNtdll = 0 then
    Exit;
  @pIsEcCode := GetProcAddress(hNtdll, 'RtlIsEcCode');
  if not Assigned(pIsEcCode) then
    Exit;
  // Query the EC code bitmap for the target address
  Result := pIsEcCode(APtr);
end;

{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：替换原有过程指针，并保留原有指针
//参数：ATargetProc：被替换过程指针， NewProc：新的过程指针。
//      OldProc: 被替换过程的备份过程指针（和原来的不是一个）
//注意：对 Delphi 的 bpl 类函数需要 FixFunc 查找真正的函数地址
//注意：需要判断是否 Win8 的 jmp xxx; int 3; ... 的特殊精简模式
//注意：64 位中会有一种情况失败，就是 VirtualAlloc 不能在被Hook函数地址正负 2Gb
//      范围内分配到内存。不过这个可能微乎其微，几乎不可能发生
////////////////////////////////////////////////////////////////////////////////
function HookProc(ATargetProc, ANewProc: Pointer; out AOldProc: Pointer): Boolean;

  // Follow indirect JMP thunks (e.g. Delphi BPL exports) to the real entry point
  procedure FixFunc(MaxDepth: Integer = 10);
  type
    TJmpCode = packed record
      Code: Word;       // Indirect jump opcode $25FF
{$IFDEF CPU_64BIT}
      RelOffset: Int32; // JMP QWORD PTR [RIP + RelOffset]
{$ELSE}
      Addr: PPointer;   // JMP DWORD PTR [Addr]; Points at the target pointer
{$ENDIF}
    end;
    PJmpCode = ^TJmpCode;
  const
    csJmp32Code = $25FF;
  var
    P: PPointer;
  begin
    if MaxDepth <= 0 then
      Exit;
    if PJmpCode(ATargetProc)^.Code = csJmp32Code then
    begin
      // Resolve the pointer stored after the indirect JMP instruction
{$IFDEF CPU_64BIT}
      P := Pointer(NativeUInt(ATargetProc) + PJmpCode(ATargetProc)^.RelOffset + SizeOf(TJmpCode));
      ATargetProc := P^;
{$ELSE}
      P := PJmpCode(ATargetProc)^.Addr;
      ATargetProc := P^;
{$ENDIF}
      FixFunc(MaxDepth - 1);
    end;
  end;
var
  oldProc: POldProc;
  newProc: PNewProc;
  backCodeSize: Integer;
  newProtected, oldProtected: DWORD;
{$IFDEF USELONGJMP}
  JmpAfterBackCode: PJMPCode;
{$ENDIF}
begin
  Result := False;
  if (ATargetProc = nil) or (ANewProc = nil) then
    Exit;

  FixFunc();
{$IFDEF CPUARM64}
  // ARM64EC: Native ARM64 targets use absolute jumps; x64 targets (e.g. system
  // DLL exports) keep the long-jump path below. The emulator handles transitions.
  if IsTargetArm64(ATargetProc) then
  begin
    Result := HookProcArm64(ATargetProc, ANewProc, AOldProc);
    Exit;
  end;
{$ENDIF}
  newProc := PNewProc(ATargetProc);
  backCodeSize := CalcHookProcSize(ATargetProc);
  if backCodeSize < 0 then
    Exit;
  // The trampoline stores the saved prologue followed by a jump appended at
  // offset backCodeSize. Refuse to hook if the two would not fit in BackCode,
  // rather than overflowing into the adjacent trampoline fields.
  if backCodeSize + SizeOf(oldProc^.JmpRealFunc) > conBackCodeSize then
    Exit;

  if not VirtualProtect(ATargetProc, backCodeSize, PAGE_EXECUTE_READWRITE, oldProtected) then
    Exit;

  AOldProc := TryAllocMem(ATargetProc, conSysPageSize);
  if AOldProc = nil then
  begin
    // Restore the original page protection before bailing out
    VirtualProtect(ATargetProc, backCodeSize, oldProtected, newProtected);
    Exit;
  end;

  FillChar(AOldProc^, SizeOf(TOldProc), $90);
  oldProc := POldProc(AOldProc);
{$IFDEF USEINT3}
  oldProc.Int3OrNop := $CC;
{$ENDIF}
  oldProc.BackUpCodeSize := backCodeSize;
  oldProc.OldFuncAddr := ATargetProc;
  Move(ATargetProc^, oldProc^.BackCode, backCodeSize);
{$IFDEF USELONGJMP}
  // Trampoline layout (x64): [saved prologue][JMP to original+size][JMP to hook].
  // The return-to-original jump is written at offset backCodeSize (JmpAfterBackCode);
  // execution reaches it by falling through the saved prologue, so that is the jump
  // actually taken on this path. oldProc^.JmpRealFunc sits at the fixed struct offset
  // and is only used by the x86 path below (reached via NOP slide); here it is kept
  // populated for layout symmetry but is not on the executed path.
  JmpAfterBackCode := PJMPCode(@oldProc^.BackCode[backCodeSize]);

  oldProc^.JmpRealFunc.JMP := $25FF;
  oldProc^.JmpRealFunc.JmpOffset := 0;
  oldProc^.JmpRealFunc.Addr := NativeUInt(ATargetProc) + backCodeSize;

  JmpAfterBackCode^.JMP := $25FF;
  JmpAfterBackCode^.JmpOffset := 0;
  JmpAfterBackCode^.Addr := NativeUInt(ATargetProc) + backCodeSize;

  oldProc^.JmpHookFunc.JMP := $25FF;
  oldProc^.JmpHookFunc.JmpOffset := 0;
  oldProc^.JmpHookFunc.Addr := NativeUInt(ANewProc);
{$ELSE}
  // Trampoline layout (x86): [saved prologue][rel JMP to original+size][rel JMP to hook].
  // Unlike the x64 path, the return jump is JmpRealFunc at the fixed struct offset:
  // the overwritten target bytes are NOP-filled, so after running the saved prologue
  // execution slides through the NOPs to JmpRealFunc. JmpAfterBackCode is not used here.
  oldProc^.JmpRealFunc.JMP := $E9;
  oldProc^.JmpRealFunc.Addr := NativeInt(ATargetProc) + backCodeSize - (NativeInt(@oldProc^.JmpRealFunc) + 5);

  oldProc^.JmpHookFunc.JMP := $E9;
  oldProc^.JmpHookFunc.Addr := NativeInt(ANewProc) - (NativeInt(@oldProc^.JmpHookFunc) + 5);
{$ENDIF}
  // Nop-fill overwritten bytes, then install a relative JMP into the trampoline
  FillChar(ATargetProc^, backCodeSize, $90);

  newProc^.JMP := $E9;
  newProc^.Addr := NativeInt(@oldProc^.JmpHookFunc) - (NativeInt(@newProc^.JMP) + 5);

  // Restoring the original protection failed, but the patch is already written
  // and functional. Returning False here would strand a live hook with a
  // dangling AOldProc and a leaked trampoline, since the caller would neither
  // use AOldProc nor call UnHookProc. Treat it as non-fatal and continue with
  // the cache flush, matching the ARM64 path (see HookProcArm64).
  if not VirtualProtect(ATargetProc, backCodeSize, oldProtected, newProtected) then
    newProtected := oldProtected;

  // Flush instruction cache so patched code is not executed from stale lines
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  FlushInstructionCache(GetCurrentProcess(), oldProc, conSysPageSize);
  Result := True;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：解除钩子
//参数：OldProc：在 HookProc 中保存的指针
////////////////////////////////////////////////////////////////////////////////
function UnHookProc(var AOldProc: Pointer): Boolean;
var
  oldProc: POldProc absolute AOldProc;
  newProc: PNewProc;
  backCodeSize: Integer;
  newProtected, oldProtected: DWORD;
begin
  Result := False;
  if AOldProc = nil then
    Exit;
  backCodeSize := oldProc^.BackUpCodeSize;
  newProc := PNewProc(oldProc^.OldFuncAddr);

  if not VirtualProtect(newProc, backCodeSize, PAGE_EXECUTE_READWRITE, oldProtected) then
    Exit;

  // Restore the original prologue bytes saved in the trampoline page
  Move(oldProc^.BackCode, newProc^, oldProc^.BackUpCodeSize);

  if not VirtualProtect(newProc, backCodeSize, oldProtected, newProtected) then
    Exit;
  VirtualFree(oldProc, 0, MEM_RELEASE);
  // Flush instruction cache so patched code is not executed from stale lines
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  AOldProc := nil;
  Result := True;
end;

end.
