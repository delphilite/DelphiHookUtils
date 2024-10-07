{ *********************************************************************** }
{                                                                         }
{   Delphi ͨ�� Hook �⣬�ӿڶ��󷽷� Hook ֧�ֵ�Ԫ                       }
{                                                                         }
{   ��ƣ�Lsuper 2016.10.01                                               }
{   ��ע��                                                                }
{   ��ˣ�                                                                }
{                                                                         }
{   Copyright (c) 1998-2021 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   2016.10.01 - Lsuper                                                   }
{                                                                         }
{   1���� HookUtils �в�� COM ��غ������� HookIntfs ��Ԫ                }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   2012.02.01 - wr960204 ��ϡ�ɣ�http://www.raysoftware.cn               }
{                                                                         }
{   1��ʹ���˿�Դ�� BeaEngine ��������棬BeaEngine �ĺô��ǿ����� BCB �� }
{      ��� OMF ��ʽ�� Obj��ֱ�����ӽ� dcu ��Ŀ���ļ��У��������� DLL   }
{   2��BeaEngine ���棺                                                   }
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
//��ƣ�Lsuper 2016.10.01
//���ܣ����� COM �����з����ĵ�ַ
//������AMethodIndex �Ƿ���������
//ע�⣺AMethodIndex �ǽӿڰ������ӿڵķ���������������:
//      IA = Interface
//      procedure A(); // ��Ϊ IA �Ǵ� IUnKnow �����ģ�IUnKnow �Լ��� 3 ���������� AMethodIndex=3
//      end;
//      IB = Interface(IA)
//      procedure B(); // ��Ϊ IB �Ǵ� IA �����ģ����� AMethodIndex=4
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
  { Delphi��COM����ķ�����Ƚ��ر�,COM�ӿ�ʵ�����Ƕ����һ����Ա,ʵ���ϵ��õ�
    ������Self������ӿڳ�Ա�ĵ�ַ,����Delphi��COM������ֱ��ָ����󷽷�,����ָ��
    һС�λ���ָ��,��Self��ȥ(�Ӹ���)�����Ա�ڶ����е�ƫ��,������Selfָ�������ת
    ����������ķ������.

    ��������Ҫ"͵��"һ�·���ָ��ָ���ͷ�����ֽ�,���������Selfָ���,��ô����Delphi
    ʵ�ֵ�COM����.���Ǿ��������������Ķ����ַ.

    �����������жϺʹ���Delphi��COM�����.��������ʵ�ֵ�COM������Զ����Ե�.
    ��Ϊ�����ĺ���ͷ�����Ƕ���ջ�׵Ĵ�����߲������ֲ������Ĵ������.
    ��������һ����������һ������,Ҳ����Self��ָ��.���Ը���������ж�.
  }
  buf := Result;
  {
    add Self,[-COM�������ʵ�ֶ���ƫ��]
    JMP  �����ķ���
    �����ľ���Delphi���ɵ�COM���󷽷���ǰ��ָ��
  }
{$IFDEF CPUX64}
  // add rcx, -COM�����ƫ��, JMP ��������ķ�����ַ,X64��ֻ��һ��stdcall����Լ��.����Լ������stdcall�ı���
  if (buf^[0] = $48) and (buf^[1] = $81) and (buf^[2] = $C1) and (buf^[7] = $E9)
  then
    Result := Pointer(NativeInt(@buf[$C]) + PDWORD(@buf^[8])^);
{$ELSE}
  // add [esp + $04],-COM�����ƫ��, JMP�����Ķ����ַ,stdcall/cdecl����Լ��
  if (buf^[0] = $81) and (buf^[1] = $44) and (buf^[2] = $24) and
    (buf^[03] = $04) and (buf^[8] = $E9) then
    Result := Pointer(NativeUInt(@buf[$D]) + PDWORD(@buf^[9])^)
  else // add eax,-COM�����ƫ��, JMP�����Ķ����ַ,�Ǿ���Register����Լ����
    if (buf^[0] = $05) and (buf^[5] = $E9) then
      Result := Pointer(NativeUInt(@buf[$A]) + PDWORD(@buf^[6])^);
{$ENDIF}
end;

////////////////////////////////////////////////////////////////////////////////
//��ƣ�Lsuper 2016.10.01
//���ܣ��� COM ���󷽷��Ĺ���
//������
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
