{ *********************************************************************** }
{                                                                         }
{   Delphi 通用 Hook 库，支持 Windows x86/x64, Ansi/Unicode               }
{                                                                         }
{   设计：Lsuper 2016.10.01                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2025 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   注意：                                                                }
{                                                                         }
{   1、Hook/Unhook 放到单元，初始化、析构中做，否则可能因改写内存没挂起   }
{      其他线程的调用而造成错误                                           }
{                                                                         }
{   限制：                                                                }
{                                                                         }
{   1、限制：不能 Hook 代码大小小于 5 个字节的函数                        }
{   2、限制：不能 Hook 前 5 个字节中有跳转指令的函数                      }
{                                                                         }
{   希望使用的朋友们自己也具有一定的汇编或者逆向知识，Hook 函数前请确定   }
{   该函数不属于上面两种情况                                              }
{                                                                         }
{   另外钩 COM 对象有一个技巧，如果你想在最早时机勾住某个 COM 对象可以在  }
{   你要钩的 COM 对象创建前自己先创建一个该对象，Hook 住然后释放你自己的  }
{   对象，这样这个函数已经被下钩子了，而且是钩在这个 COM 对象创建前的     }
{                                                                         }
{ *********************************************************************** }
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

{.$DEFINE USEINT3} { 在机器指令中插入 INT3，断点指令方便调试 }

interface

function HookProc(ATargetProc, ANewProc: Pointer;
  out AOldProc: Pointer): Boolean; overload;
function HookProc(const ATargetModule, ATargetProc: string; ANewProc: Pointer;
  out AOldProc: Pointer): Boolean; overload;
function UnHookProc(var AOldProc: Pointer): Boolean;

implementation

{$IFDEF CPUX64}
  {$DEFINE USELONGJMP}
{$ENDIF}

uses
  Windows;

const
  GPageSize: Integer    = 4096;

type
{$IFNDEF FPC} {$IF CompilerVersion < 23}
  NativeUInt = LongWord;
{$IFEND} {$ENDIF}

  TJMPCode = packed record
{$IFDEF USELONGJMP}
    JMP: Word;
    JmpOffset: Int32;
    Addr: NativeUInt;
{$ELSE}
    JMP: Byte;
    Addr: NativeUInt;
{$ENDIF}
  end;
  PJMPCode = ^TJMPCode;

  TOldProc = packed record
{$IFDEF USEINT3}
    Int3OrNop: Byte;
{$ENDIF}
    BackCode: array[0..$20 - 1] of Byte;
    JmpRealFunc: TJMPCode;
    JmpHookFunc: TJMPCode;

    BackUpCodeSize: Integer;
    OldFuncAddr: Pointer;
  end;
  POldProc = ^TOldProc;

  TNewProc = packed record
    JMP: Byte;
    Addr: Integer;
  end;
  PNewProc = ^TNewProc;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：引入 LDE64 长度反编译引擎 ShellCode
//参数：
////////////////////////////////////////////////////////////////////////////////
const
{$IFDEF CPUX64}
  {$I 'HookUtils.64.inc'} { from LDE64-x64.rar\LDE64x64.bin }
{$ELSE}
  {$I 'HookUtils.32.inc'} { from LDE64-x86.rar\LDE64-x86\LDE64.bin }
{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：LDE64 长度反编译引擎函数定义
//参数：
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
  if VirtualQuery(D, M, SizeOf(M)) <> 0 then
    if M.Protect <> PAGE_EXECUTE_WRITECOPY then
      VirtualProtect(D, SizeOf(defLde64ShellCode), PAGE_EXECUTE_WRITECOPY, @F);
  P := D;
  Result := P(lpData, arch);
end;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：计算需要覆盖的机器指令大小，借助了 LDE64 反汇编引擎以免指令被从中间切开
//参数：
////////////////////////////////////////////////////////////////////////////////
function CalcHookProcSize(AFunc: Pointer): Integer;
const
  lde_archi_32          = 0;
  lde_archi_64          = 64;
{$IFDEF CPUX64}
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
  while Result < SizeOf(TNewProc) do
  begin
    nLen := LDE(pCode, lde_archi_default);
    Inc(pCode, nLen);
    Inc(Result, nLen);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//修改：Lsuper 2016.10.01
//功能：
//参数：
//注意：尝试在指定指针 APtr 的正负 2Gb 以内分配内存，32 位肯定是这样的
//      64 位 JMP 都是相对的，操作数是 32 位整数，所以必须保证新的函数在旧函数
//      的正负2GB内，否则没法跳转到或者跳转回来
////////////////////////////////////////////////////////////////////////////////
function TryAllocMem(APtr: Pointer; ASize: LongWord): Pointer;
const
{$IFDEF CPUX64}
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
//功能：挂接 API
//参数：
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

  procedure FixFunc(MaxDepth: Integer = 10);
  type
    TJmpCode = packed record
      Code: Word;                 // 间接跳转指定，为 $25FF
{$IFDEF CPUX64}
      RelOffset: Int32;           // JMP QWORD PTR [RIP + RelOffset]
{$ELSE}
      Addr: PPointer;             // JMP DWORD PTR [JMPPtr] 跳转指针地址，指向保存目标地址的指针
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
{$IFDEF CPUX64}
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
  newProc := PNewProc(ATargetProc);
  backCodeSize := CalcHookProcSize(ATargetProc);
  if backCodeSize < 0 then
    Exit;

  if not VirtualProtect(ATargetProc, backCodeSize, PAGE_EXECUTE_READWRITE, oldProtected) then
    Exit;

  AOldProc := TryAllocMem(ATargetProc, GPageSize);
  if AOldProc = nil then
    Exit;

  FillChar(AOldProc^, SizeOf(TOldProc), $90);
  oldProc := POldProc(AOldProc);
{$IFDEF USEINT3}
  oldProc.Int3OrNop := $CC;
{$ENDIF}
  oldProc.BackUpCodeSize := backCodeSize;
  oldProc.OldFuncAddr := ATargetProc;
  Move(ATargetProc^, oldProc^.BackCode, backCodeSize);
{$IFDEF USELONGJMP}
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
  oldProc^.JmpRealFunc.JMP := $E9;
  oldProc^.JmpRealFunc.Addr := NativeInt(ATargetProc) + backCodeSize - (NativeInt(@oldProc^.JmpRealFunc) + 5);

  oldProc^.JmpHookFunc.JMP := $E9;
  oldProc^.JmpHookFunc.Addr := NativeInt(ANewProc) - (NativeInt(@oldProc^.JmpHookFunc) + 5);
{$ENDIF}
  // 初始化跳转
  FillChar(ATargetProc^, backCodeSize, $90);

  newProc^.JMP := $E9;
  newProc^.Addr := NativeInt(@oldProc^.JmpHookFunc) - (NativeInt(@newProc^.JMP) + 5);

  if not VirtualProtect(ATargetProc, backCodeSize, oldProtected, newProtected) then
    Exit;
  // 刷新处理器中的指令缓存，以免这部分指令被缓存执行的时候不一致
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  FlushInstructionCache(GetCurrentProcess(), oldProc, GPageSize);
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

  Move(oldProc^.BackCode, newProc^, oldProc^.BackUpCodeSize);

  if not VirtualProtect(newProc, backCodeSize, oldProtected, newProtected) then
    Exit;
  VirtualFree(oldProc, 0, MEM_RELEASE);
  // 刷新处理器中的指令缓存，以免这部分指令被缓存执行的时候不一致
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  AOldProc := nil;
  Result := True;
end;

end.
