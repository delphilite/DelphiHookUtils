{ *********************************************************************** }
{                                                                         }
{   Delphi 通用 Hook 库，接口对象方法 Hook 支持单元                       }
{                                                                         }
{   设计：Lsuper 2016.10.01                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2021 Super Studio                                  }
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
//设计: Lsuper 2016.10.01
//功能: 计算 COM 对象中方法的地址
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
  pp := PPointer(AInterface)^;
  Inc(pp, AMethodIndex);
  Result := pp^;
  { Delphi的COM对象的方法表比较特别,COM接口实际上是对象的一个成员,实际上调用到
    方法后Self是这个接口成员的地址,所以Delphi的COM方法不直接指向对象方法,而是指向
    一小段机器指令,把Self减去(加负数)这个成员在对象中的偏移,修正好Self指针后再跳转
    到真正对象的方法入口.

    所以这里要"偷窥"一下方法指针指向的头几个字节,如果是修正Self指针的,那么就是Delphi
    实现的COM对象.我们就再往下找真正的对象地址.

    下面代码就是判断和处理Delphi的COM对象的.其他语言实现的COM对象会自动忽略的.
    因为正常的函数头部都是对于栈底的处理或者参数到局部变量的处理代码.
    绝不可能一上来修正第一个参数,也就是Self的指针.所以根据这个来判断.
  }
  buf := Result;
  {
    add Self,[-COM对象相对实现对象偏移]
    JMP  真正的方法
    这样的就是Delphi生成的COM对象方法的前置指令
  }
{$IFDEF CPUX64}
  // add rcx, -COM对象的偏移, JMP 真正对象的方法地址,X64中只有一种stdcall调用约定.其他约定都是stdcall的别名
  if (buf^[0] = $48) and (buf^[1] = $81) and (buf^[2] = $C1) and (buf^[7] = $E9)
  then
    Result := Pointer(NativeInt(@buf[$C]) + PDWORD(@buf^[8])^);
{$ELSE}
  // add [esp + $04],-COM对象的偏移, JMP真正的对象地址,stdcall/cdecl调用约定
  if (buf^[0] = $81) and (buf^[1] = $44) and (buf^[2] = $24) and
    (buf^[03] = $04) and (buf^[8] = $E9) then
    Result := Pointer(NativeUInt(@buf[$D]) + PDWORD(@buf^[9])^)
  else // add eax,-COM对象的偏移, JMP真正的对象地址,那就是Register调用约定的
    if (buf^[0] = $05) and (buf^[5] = $E9) then
      Result := Pointer(NativeUInt(@buf[$A]) + PDWORD(@buf^[6])^);
{$ENDIF}
end;

////////////////////////////////////////////////////////////////////////////////
//设计: Lsuper 2016.10.01
//功能: 下 COM 对象方法的钩子
//参数：
////////////////////////////////////////////////////////////////////////////////
function HookInterface(var AInterface; AMethodIndex: Integer;
  ANewProc: Pointer; out AOldProc: Pointer): Boolean;
var
  P: Pointer;
begin
  P := CalcInterfaceMethodAddr(AInterface, AMethodIndex);
  Result := HookUtils.HookProc(P, ANewProc, AOldProc);
end;

function UnHookInterface(var AOldProc: Pointer): Boolean;
begin
  Result := HookUtils.UnHookProc(AOldProc);
end;

end.
