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
{   2016.10.01 - Lsuper                                                   }
{                                                                         }
{   1、由 HookUtils 中拆分 COM 相关函数至此 HookIntfs 单元                }
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
  HookUtils;

type
{$IFNDEF FPC} {$IF CompilerVersion < 23}
  NativeUInt = LongWord;
{$IFEND} {$ENDIF}
  PDWORD = ^LongWord;

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
  buf: PBuf;
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

  buf := Result;

  // Typical Delphi COM stub layout:
  // ADD Self, [-offset of COM field in implementing object]
  // JMP Real method

{$IFDEF CPUX64}
  // ADD RCX, -COM field offset; JMP to real method (x64 stdcall)
  if (buf^[0] = $48) and (buf^[1] = $81) and (buf^[2] = $C1) and (buf^[7] = $E9)
  then
    Result := Pointer(NativeInt(@buf[$C]) + PDWORD(@buf^[8])^);
{$ELSE}
  // ADD [ESP+$04], -COM field offset; JMP to real method (stdcall/cdecl)
  if (buf^[0] = $81) and (buf^[1] = $44) and (buf^[2] = $24) and
    (buf^[03] = $04) and (buf^[8] = $E9) then
    Result := Pointer(NativeUInt(@buf[$D]) + PDWORD(@buf^[9])^)
  else
    // ADD EAX, -COM field offset; JMP to real method (register calling convention)
    if (buf^[0] = $05) and (buf^[5] = $E9) then
      Result := Pointer(NativeUInt(@buf[$A]) + PDWORD(@buf^[6])^);
{$ENDIF}
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
var
  P: Pointer;
begin
  // Resolve the concrete method entry, then delegate to HookProc
  P := CalcInterfaceMethodAddr(AInterface, AMethodIndex);
  Result := HookUtils.HookProc(P, ANewProc, AOldProc);
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2016.10.01
//功能：解除接口方法钩子
//参数：AOldProc HookInterface 返回的跳板指针（解除后置 nil）
//返回：成功 True，失败 False
////////////////////////////////////////////////////////////////////////////////
function UnHookInterface(var AOldProc: Pointer): Boolean;
begin
  Result := HookUtils.UnHookProc(AOldProc);
end;

end.
