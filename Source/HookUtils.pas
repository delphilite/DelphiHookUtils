{ *********************************************************************** }
{                                                                         }
{   Delphi ͨ�� Hook �⣬֧�� Windows x86/x64, Ansi/Unicode               }
{                                                                         }
{   ��ƣ�Lsuper 2016.10.01                                               }
{   ��ע��                                                                }
{   ��ˣ�                                                                }
{                                                                         }
{   Copyright (c) 1998-2021 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   ע�⣺                                                                }
{                                                                         }
{   1��Hook/Unhook �ŵ���Ԫ����ʼ������������������������д�ڴ�û����   }
{      �����̵߳ĵ��ö���ɴ���                                           }
{                                                                         }
{   ���ƣ�                                                                }
{                                                                         }
{   1�����ƣ����� Hook �����СС�� 5 ���ֽڵĺ���                        }
{   2�����ƣ����� Hook ǰ 5 ���ֽ�������תָ��ĺ���                      }
{                                                                         }
{   ϣ��ʹ�õ��������Լ�Ҳ����һ���Ļ���������֪ʶ��Hook ����ǰ��ȷ��   }
{   �ú��������������������                                              }
{                                                                         }
{   ���⹳ COM ������һ�����ɣ��������������ʱ����סĳ�� COM ���������  }
{   ��Ҫ���� COM ���󴴽�ǰ�Լ��ȴ���һ���ö���Hook סȻ���ͷ����Լ���  }
{   ����������������Ѿ����¹����ˣ������ǹ������ COM ���󴴽�ǰ��     }
{                                                                         }
{ *********************************************************************** }
{                                                                         }
{   2016.10.01 - Lsuper                                                   }
{                                                                         }
{   1���ο� wr960204 ��ϡ�� ��ԭʼʵ�֣�                                  }
{      https://code.google.com/p/delphi-hook-library                      }
{   2���޸� BeaEngine ����Ϊ LDE64 ���ȷ��������棬������ʹ�С           }
{      https://github.com/BeaEngine/lde64                                 }
{      http://www.beaengine.org/download/LDE64-x86.zip                    }
{      http://www.beaengine.org/download/LDE64-x64.rar                    }
{   3��ȥ��ԭʼʵ�ֶԶ��̶߳���Ĵ���ͨ������ Hook/Unhook �ŵ���Ԫ      }
{      ��ʼ������������������������д�ڴ�û���������߳���ɴ���         }
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

unit HookUtils;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$RANGECHECKS OFF}

{.$DEFINE USEINT3} { �ڻ���ָ���в��� INT3���ϵ�ָ������ }

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
  defAllocMemPageSize   = 4096;

type
{$IFNDEF FPC} {$IF CompilerVersion < 23}
  NativeUInt = LongWord;
{$IFEND} {$ENDIF}

  TJMPCode = packed record
{$IFDEF USELONGJMP}
    JMP: Word;
    JmpOffset: Int32;
    Addr: UIntPtr;
{$ELSE}
    JMP: Byte;
    Addr: UINT_PTR;
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
//�޸ģ�Lsuper 2016.10.01
//���ܣ����� LDE64 ���ȷ��������� ShellCode
//������
////////////////////////////////////////////////////////////////////////////////
const
{$IFDEF CPUX64}
  {$I 'HookUtils.64.inc'}
{$ELSE}
  {$I 'HookUtils.32.inc'}
{$ENDIF}

////////////////////////////////////////////////////////////////////////////////
//�޸ģ�Lsuper 2016.10.01
//���ܣ�LDE64 ���ȷ��������溯������
//������
//ע�⣺x64 ����Ҫ���� DEP ����
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
//�޸ģ�Lsuper 2016.10.01
//���ܣ�������Ҫ���ǵĻ���ָ���С�������� LDE64 �������������ָ����м��п�
//������
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
  pCode := AFunc;
  while Result < SizeOf(TNewProc) do
  begin
    nLen := LDE(pCode, lde_archi_default);
    Inc(pCode, nLen);
    Inc(Result, nLen);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//�޸ģ�Lsuper 2016.10.01
//���ܣ�
//������
//ע�⣺������ָ��ָ�� APtr ������ 2Gb ���ڷ����ڴ棬32 λ�϶���������
//      64 λ JMP ������Եģ��������� 32 λ���������Ա��뱣֤�µĺ����ھɺ���
//      ������2GB�ڣ�����û����ת��������ת����
////////////////////////////////////////////////////////////////////////////////
function TryAllocMem(APtr: Pointer; ASize: LongWord): Pointer;
const
{$IFDEF CPUX64}
  defAllocationType     = MEM_COMMIT or MEM_RESERVE or MEM_TOP_DOWN;
{$ELSE}
  defAllocationType     = MEM_COMMIT or MEM_RESERVE;
{$ENDIF}
  KB: Int64 = 1024;
  MB: Int64 = 1024 * 1024;
  GB: Int64 = 1024 * 1024 * 1024;
var
  mbi: TMemoryBasicInformation;
  Min, Max: Int64;
  pbAlloc: Pointer;
  sSysInfo: TSystemInfo;
begin
  GetSystemInfo(sSysInfo);
  if NativeUInt(APtr) <= 2 * GB then
    Min := 1
  else Min := NativeUInt(APtr) - 2 * GB;
  Max := NativeUInt(APtr) + 2 * GB;

  Result := nil;
  pbAlloc := Pointer(Min);
  while NativeUInt(pbAlloc) < Max do
  begin
    if (VirtualQuery(pbAlloc, mbi, SizeOf(mbi)) = 0) then
      Break;
    if ((mbi.State or MEM_FREE) = MEM_FREE) and (mbi.RegionSize >= ASize) and
      (mbi.RegionSize >= sSysInfo.dwAllocationGranularity) then
    begin
      pbAlloc := PByte(NativeUInt((NativeUInt(pbAlloc) + (sSysInfo.dwAllocationGranularity - 1)) div
        sSysInfo.dwAllocationGranularity) * sSysInfo.dwAllocationGranularity);
      Result := VirtualAlloc(pbAlloc, ASize, defAllocationType, PAGE_EXECUTE_READWRITE);
      if Result <> nil then
        Break;
    end;
    pbAlloc := Pointer(NativeUInt(mbi.BaseAddress) + mbi.RegionSize);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//��ƣ�Lsuper 2016.10.01
//���ܣ��ҽ� API
//������
//ע�⣺��� ATargetModule û�б� LoadLibrary �� Hook ��ʧ�ܣ��������ֹ� Load
////////////////////////////////////////////////////////////////////////////////
function HookProc(const ATargetModule, ATargetProc: string; ANewProc: Pointer;
  out AOldProc: Pointer): Boolean;
var
  nHandle: THandle;
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
//��ƣ�Lsuper 2016.10.01
//���ܣ��滻ԭ�й���ָ�룬������ԭ��ָ��
//������ATargetProc�����滻����ָ�룬 NewProc���µĹ���ָ�롣
//      OldProc: ���滻���̵ı��ݹ���ָ�루��ԭ���Ĳ���һ����
//ע�⣺�� Delphi �� bpl �ຯ����Ҫ FixFunc ���������ĺ�����ַ
//ע�⣺��Ҫ�ж��Ƿ� Win8 �� jmp xxx; int 3; ... �����⾫��ģʽ
//ע�⣺64 λ�л���һ�����ʧ�ܣ����� VirtualAlloc �����ڱ�Hook������ַ���� 2Gb
//      ��Χ�ڷ��䵽�ڴ档�����������΢����΢�����������ܷ���
////////////////////////////////////////////////////////////////////////////////
function HookProc(ATargetProc, ANewProc: Pointer; out AOldProc: Pointer): Boolean;

  procedure FixFunc();
  type
    TJmpCode = packed record
      Code: Word;                 // �����תָ����Ϊ $25FF
{$IFDEF CPUX64}
      RelOffset: Int32;           // JMP QWORD PTR [RIP + RelOffset]
{$ELSE}
      Addr: PPointer;             // JMP DWORD PTR [JMPPtr] ��תָ���ַ��ָ�򱣴�Ŀ���ַ��ָ��
{$ENDIF}
    end;
    PJmpCode = ^TJmpCode;
  const
    csJmp32Code = $25FF;
  var
    P: PPointer;
  begin
    if PJmpCode(ATargetProc)^.Code = csJmp32Code then
    begin
{$IFDEF CPUX64}
      P := Pointer(NativeUInt(ATargetProc) + PJmpCode(ATargetProc)^.RelOffset + SizeOf(TJmpCode));
      ATargetProc := P^;
{$ELSE}
      P := PJmpCode(ATargetProc)^.Addr;
      ATargetProc := P^;
{$ENDIF}
      FixFunc();
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

  if not VirtualProtect(ATargetProc, backCodeSize, PAGE_EXECUTE_READWRITE,
    oldProtected) then
    Exit;

  AOldProc := TryAllocMem(ATargetProc, defAllocMemPageSize);
  // AOldProc := VirtualAlloc(nil, defAllocMemPageSize, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  if AOldProc = nil then
    Exit;

  FillMemory(AOldProc, SizeOf(TOldProc), $90);
  oldProc := POldProc(AOldProc);
{$IFDEF USEINT3}
  oldProc.Int3OrNop := $CC;
{$ENDIF}
  oldProc.BackUpCodeSize := backCodeSize;
  oldProc.OldFuncAddr := ATargetProc;
  CopyMemory(@oldProc^.BackCode, ATargetProc, backCodeSize);
{$IFDEF USELONGJMP}
  JmpAfterBackCode := PJMPCode(@oldProc^.BackCode[backCodeSize]);

  oldProc^.JmpRealFunc.JMP := $25FF;
  oldProc^.JmpRealFunc.JmpOffset := 0;
  oldProc^.JmpRealFunc.Addr := UIntPtr(Int64(ATargetProc) + backCodeSize);

  JmpAfterBackCode^.JMP := $25FF;
  JmpAfterBackCode^.JmpOffset := 0;
  JmpAfterBackCode^.Addr := UIntPtr(Int64(ATargetProc) + backCodeSize);

  oldProc^.JmpHookFunc.JMP := $25FF;
  oldProc^.JmpHookFunc.JmpOffset := 0;
  oldProc^.JmpHookFunc.Addr := UIntPtr(ANewProc);
{$ELSE}
  oldProc^.JmpRealFunc.JMP := $E9;
  oldProc^.JmpRealFunc.Addr := (NativeInt(ATargetProc) + backCodeSize) -
    (NativeInt(@oldProc^.JmpRealFunc) + 5);

  oldProc^.JmpHookFunc.JMP := $E9;
  oldProc^.JmpHookFunc.Addr := NativeInt(ANewProc) -
    (NativeInt(@oldProc^.JmpHookFunc) + 5);
{$ENDIF}
  // Init
  FillMemory(ATargetProc, backCodeSize, $90);

  newProc^.JMP := $E9;
  newProc^.Addr := NativeInt(@oldProc^.JmpHookFunc) -
    (NativeInt(@newProc^.JMP) + 5);;
  // NativeInt(ANewProc) - (NativeInt(@newProc^.JMP) + 5);

  if not VirtualProtect(ATargetProc, backCodeSize, oldProtected, newProtected) then
    Exit;
  // ˢ�´������е�ָ��棬�����ⲿ��ָ�����ִ�е�ʱ��һ��
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  FlushInstructionCache(GetCurrentProcess(), oldProc, defAllocMemPageSize);
  Result := True;
end;

////////////////////////////////////////////////////////////////////////////////
//��ƣ�Lsuper 2016.10.01
//���ܣ��������
//������OldProc���� HookProc �б����ָ��
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

  CopyMemory(newProc, @oldProc^.BackCode, oldProc^.BackUpCodeSize);

  if not VirtualProtect(newProc, backCodeSize, oldProtected, newProtected) then
    Exit;
  VirtualFree(oldProc, defAllocMemPageSize, MEM_FREE);
  // ˢ�´������е�ָ��棬�����ⲿ��ָ�����ִ�е�ʱ��һ��
  FlushInstructionCache(GetCurrentProcess(), newProc, backCodeSize);
  AOldProc := nil;
  Result := True;
end;

end.
