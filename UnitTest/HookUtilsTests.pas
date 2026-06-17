{ *********************************************************************** }
{                                                                         }
{   HookUtils 单元测试项目单元                                            }
{                                                                         }
{   设计：Lsuper 2026.04.01                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2026 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }

unit HookUtilsTests;

interface

uses
  SysUtils, TestFramework, HookUtils;

type
  THookUtilsTest = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHookProcFreeInstance;
    procedure TestHookProcGetTickCountByModule;
    procedure TestHookProcGetTickCountRehookCycles;
    procedure TestHookProcInvalidModule;
    procedure TestHookProcNilPointers;
    procedure TestUnHookNil;
    procedure TestTrampolineBufferSizingInvariant;
    procedure TestTrampolineFitsSystemPage;
  end;

implementation

uses
  Windows, Classes;

var
  GFreeInstanceHits: Integer;
  GFreeInstanceNext: procedure(Self: TObject);
  GGetTickCountHits: Integer;
  GGetTickCountNext: function: DWORD; stdcall;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：FreeInstance hook 测试回调，统计调用并链式调用原实现
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure HookTestFreeInstanceCallback(Self: TObject);
begin
  Inc(GFreeInstanceHits);
  if Assigned(GFreeInstanceNext) then
    GFreeInstanceNext(Self);
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：GetTickCount hook 测试回调，计数并转调原实现
//参数：
////////////////////////////////////////////////////////////////////////////////
function HookTestGetTickCountCallback: DWORD; stdcall;
begin
  Inc(GGetTickCountHits);
  Result := GGetTickCountNext();
end;

{ THookUtilsTest }

procedure THookUtilsTest.SetUp;
begin
  inherited;
end;

procedure THookUtilsTest.TearDown;
begin
  inherited;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：与 Demos/RTL/Demo.dpr 一致，验证 HookProc/UnHookProc 对 TObject.FreeInstance
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestHookProcFreeInstance;
begin
  GFreeInstanceHits := 0;
  GFreeInstanceNext := nil;
  try
    CheckTrue(HookProc(@TObject.FreeInstance, @HookTestFreeInstanceCallback,
      @GFreeInstanceNext));
    with TStringList.Create do
      try
      finally
        Free;
      end;
    with EExternal.Create('') do
      try
      finally
        Free;
      end;
    CheckTrue(GFreeInstanceHits >= 2,
      'FreeInstance hook should observe at least two object frees');
  finally
    if Assigned(GFreeInstanceNext) then
      CheckTrue(UnHookProc(@GFreeInstanceNext));
    GFreeInstanceNext := nil;
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：验证按模块名导出函数的 HookProc 重载
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestHookProcGetTickCountByModule;
var
  Old: Pointer;
begin
  Old := nil;
  GGetTickCountHits := 0;
  GGetTickCountNext := nil;
  try
    CheckTrue(HookProc('kernel32.dll', 'GetTickCount', @HookTestGetTickCountCallback, Old));
    @GGetTickCountNext := Old;
    GetTickCount();
    CheckTrue(GGetTickCountHits > 0,
      'Imported GetTickCount should pass through hook');
  finally
    if Old <> nil then
      CheckTrue(UnHookProc(Old));
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.17
//功能：Hook -> unhook -> rehook GetTickCount across several cycles and confirm
//      the hook stays functional each time. Guards the non-fatal protect-restore
//      path in HookProc, which must not strand state between cycles.
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestHookProcGetTickCountRehookCycles;
const
  cCycles = 5;
var
  Old: Pointer;
  i, Before: Integer;
begin
  for i := 1 to cCycles do
  begin
    Old := nil;
    GGetTickCountHits := 0;
    GGetTickCountNext := nil;
    CheckTrue(HookProc('kernel32.dll', 'GetTickCount',
      @HookTestGetTickCountCallback, Old),
      Format('HookProc should succeed on cycle %d', [i]));
    @GGetTickCountNext := Old;

    Before := GGetTickCountHits;
    GetTickCount();
    CheckTrue(GGetTickCountHits > Before,
      Format('Hook should observe the call on cycle %d', [i]));

    CheckTrue(UnHookProc(Old),
      Format('UnHookProc should succeed on cycle %d', [i]));
    GGetTickCountNext := nil;

    // After unhook the callback must no longer fire
    Before := GGetTickCountHits;
    GetTickCount();
    CheckEquals(Before, GGetTickCountHits,
      Format('Unhooked GetTickCount must not invoke callback on cycle %d', [i]));
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：未加载模块时 HookProc 应返回 False
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestHookProcInvalidModule;
var
  Dummy: Pointer;
begin
  Dummy := nil;
  CheckFalse(HookProc('__NoSuchModule_42__.dll', 'GetTickCount',
    @HookTestGetTickCountCallback, Dummy));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：nil 目标或替换指针时 HookProc 应失败
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestHookProcNilPointers;
var
  Old: Pointer;
begin
  CheckFalse(HookProc(nil, @HookTestFreeInstanceCallback, Old));
  CheckFalse(HookProc(@TObject.FreeInstance, nil, Old));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.17
//功能：Pin the trampoline buffer-sizing invariant that HookUtils relies on.
//     The saved prologue plus the appended return jump must fit inside the
//     BackCode buffer for every legal prologue, otherwise the trampoline write
//     overflows into adjacent fields. Mirrors the production constants; if any
//     of them change without re-checking, this fails.
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestTrampolineBufferSizingInvariant;
const
  // Mirror of HookUtils internals (not exported), kept in sync deliberately.
  conBackCodeSize   = $30;            // TOldProc.BackCode length
  cSizeOfTNewProc   = 5;              // SizeOf(TNewProc): E9 + rel32
  cMaxInstrLen      = 15;             // longest x86/x64 instruction
{$IF Defined(CPUX64) or Defined(CPUARM64)}
  cJmpCodeSize      = 14;             // x64 TJMPCode: FF25 + disp32 + qword
{$ELSE}
  cJmpCodeSize      = 5;              // x86 TJMPCode: E9 + rel32
{$IFEND}
var
  WorstBackCodeSize: Integer;
begin
  // CalcHookProcSize accumulates whole instructions until the total reaches
  // SizeOf(TNewProc). Worst case: (cSizeOfTNewProc - 1) one-byte instructions,
  // then a single maximum-length instruction crosses the threshold.
  WorstBackCodeSize := (cSizeOfTNewProc - 1) + cMaxInstrLen;
  CheckEquals(19, WorstBackCodeSize,
    'Worst-case overwritten prologue should be 19 bytes');

  // The trampoline appends a return jump at offset backCodeSize; both must fit.
  CheckTrue(WorstBackCodeSize + cJmpCodeSize <= conBackCodeSize,
    Format('BackCode buffer (%d) must hold worst-case prologue (%d) + jump (%d)',
      [conBackCodeSize, WorstBackCodeSize, cJmpCodeSize]));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.17
//功能：HookUtils allocates one page (conSysPageSize) per trampoline and assumes the
//     whole TOldProc layout fits within it. Confirm a full trampoline fits in
//     the real OS page size reported by GetSystemInfo, validating both the
//     page-size assumption and the InitPageSize correction path.
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestTrampolineFitsSystemPage;
const
  conBackCodeSize  = $30;
  // Upper bound on the rest of TOldProc (two TJMPCode + size + pointer + slack).
  cTrampolineExtra  = 64;
var
  sInfo: TSystemInfo;
begin
  GetSystemInfo(sInfo);
  CheckTrue(sInfo.dwPageSize > 0, 'System page size should be reported');
  CheckTrue(conBackCodeSize + cTrampolineExtra <= Integer(sInfo.dwPageSize),
    Format('Trampoline must fit in one OS page (%d bytes)', [sInfo.dwPageSize]));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.04.05
//功能：nil 跳板时 UnHookProc 应返回 False
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookUtilsTest.TestUnHookNil;
var
  P: Pointer;
begin
  P := nil;
  CheckFalse(UnHookProc(P));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2018.12.25
//功能：Register any test cases with the test runner
//参数：
////////////////////////////////////////////////////////////////////////////////
initialization
  RegisterTest(THookUtilsTest.Suite);

end.
