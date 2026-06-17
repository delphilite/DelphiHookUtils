{ *********************************************************************** }
{                                                                         }
{   HookIntfs 单元测试项目单元                                            }
{                                                                         }
{   设计：Lsuper 2026.06.14                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2026 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }

unit HookIntfsTests;

interface

uses
  SysUtils, TestFramework, HookIntfs;

type
  THookIntfsTest = class(TTestCase)
  strict private
    FShellLink: IUnknown;
    FNeedCoUninit: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCalcInterfaceMethodAddrShellLinkSetPath;
    procedure TestHookInterfaceNilNewProc;
    procedure TestHookInterfaceShellLinkSetPath;
    procedure TestHookInterfaceShellLinkSetPathRehook;
    procedure TestUnHookInterfaceNil;
  end;

implementation

uses
  ActiveX, ShlObj, Windows, ComObj;

const
  cShellLinkSetPathIndex = 20;

  cHookRedirectPath     = 'C:\Windows';
  cHookCycleInput1      = 'c:\HookCycle1';
  cHookCycleInput2      = 'c:\HookCycle2';
  cDirectAfterUnhook1   = 'c:\DirectAfterUnhook1';
  cDirectAfterUnhook2   = 'c:\DirectAfterUnhook2';

var
  GShellLinkSetPathHits: Integer;
  GShellLinkSetPathLastArg: string;
  GShellLinkSetPathNext: function(Self: IShellLink; pszFile: PChar): HResult; stdcall;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.14
//功能：IShellLink.SetPath hook 测试回调，统计调用并链式调用原实现
//参数：
////////////////////////////////////////////////////////////////////////////////
function HookTestShellLinkSetPathCallback(Self: IShellLink; pszFile: PChar): HResult; stdcall;
begin
  Inc(GShellLinkSetPathHits);
  GShellLinkSetPathLastArg := string(pszFile);
  Result := GShellLinkSetPathNext(Self, PChar(cHookRedirectPath));
end;

{ THookIntfsTest }

procedure THookIntfsTest.SetUp;
begin
  inherited;
  FNeedCoUninit := CoInitialize(nil) = S_OK;
  FShellLink := CreateComObject(CLSID_ShellLink);
end;

procedure THookIntfsTest.TearDown;
begin
  if Assigned(GShellLinkSetPathNext) then
  begin
    UnHookInterface(@GShellLinkSetPathNext);
    GShellLinkSetPathNext := nil;
  end;
  FShellLink := nil;
  if FNeedCoUninit then
    CoUninitialize;
  inherited;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.14
//功能：与 Demos/VCL/MainFrm.pas 一致，验证 CalcInterfaceMethodAddr 能解析
//      IShellLink.SetPath 的真实方法地址
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookIntfsTest.TestCalcInterfaceMethodAddrShellLinkSetPath;
var
  Addr: Pointer;
begin
  Addr := CalcInterfaceMethodAddr(FShellLink, cShellLinkSetPathIndex);
  CheckNotNull(Addr, 'SetPath method address should be resolved');
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.14
//功能：nil 替换过程时 HookInterface 应失败
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookIntfsTest.TestHookInterfaceNilNewProc;
var
  Dummy: Pointer;
begin
  Dummy := nil;
  CheckFalse(HookInterface(FShellLink, cShellLinkSetPathIndex, nil, Dummy));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.14
//功能：与 Demos/VCL/MainFrm.pas cbHookCOMClick 一致，验证 HookInterface 能
//      拦截 IShellLink.SetPath 并改写参数
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookIntfsTest.TestHookInterfaceShellLinkSetPath;
var
  ShellLink: IShellLink;
  HR: HResult;
  PathBuf: array [0 .. MAX_PATH] of Char;
  FindData: TWin32FindData;
begin
  ShellLink := FShellLink as IShellLink;
  GShellLinkSetPathHits := 0;
  GShellLinkSetPathLastArg := '';
  GShellLinkSetPathNext := nil;
  try
    CheckTrue(HookInterface(ShellLink, cShellLinkSetPathIndex,
      @HookTestShellLinkSetPathCallback, @GShellLinkSetPathNext));
    HR := ShellLink.SetPath('c:\HookTestInput');
    CheckTrue(Succeeded(HR), 'SetPath should succeed through hook');
    CheckTrue(GShellLinkSetPathHits > 0,
      'SetPath hook should observe at least one call');
    CheckEquals('c:\HookTestInput', GShellLinkSetPathLastArg,
      'Hook callback should receive original SetPath argument');
    FillChar(PathBuf, SizeOf(PathBuf), 0);
    HR := ShellLink.GetPath(PathBuf, MAX_PATH, FindData, SLGP_RAWPATH);
    CheckTrue(Succeeded(HR), 'GetPath should succeed after hooked SetPath');
    CheckEquals(cHookRedirectPath, string(PathBuf),
      'Hook callback should redirect SetPath to C:\Windows');
  finally
    if Assigned(GShellLinkSetPathNext) then
      CheckTrue(UnHookInterface(@GShellLinkSetPathNext));
    GShellLinkSetPathNext := nil;
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.16
//功能：验证 hook → unhook → 再次 hook → unhook 后功能仍正常
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookIntfsTest.TestHookInterfaceShellLinkSetPathRehook;
var
  ShellLink: IShellLink;
  HR: HResult;
  PathBuf: array [0 .. MAX_PATH] of Char;
  FindData: TWin32FindData;
  HitsAfterFirstHook: Integer;
  HitsAfterSecondHook: Integer;

  procedure AssertHookedSetPath(const AInputPath: string);
  begin
    HR := ShellLink.SetPath(PChar(AInputPath));
    CheckTrue(Succeeded(HR), 'SetPath should succeed through hook');
    CheckTrue(GShellLinkSetPathHits > 0,
      'SetPath hook should observe at least one call');
    CheckEquals(AInputPath, GShellLinkSetPathLastArg,
      'Hook callback should receive original SetPath argument');
    FillChar(PathBuf, SizeOf(PathBuf), 0);
    HR := ShellLink.GetPath(PathBuf, MAX_PATH, FindData, SLGP_RAWPATH);
    CheckTrue(Succeeded(HR), 'GetPath should succeed after hooked SetPath');
    CheckEquals(cHookRedirectPath, string(PathBuf),
      'Hook callback should redirect SetPath to C:\Windows');
  end;

  procedure AssertDirectSetPath(const APath: string);
  begin
    HR := ShellLink.SetPath(PChar(APath));
    CheckTrue(Succeeded(HR), 'SetPath should succeed without hook');
    FillChar(PathBuf, SizeOf(PathBuf), 0);
    HR := ShellLink.GetPath(PathBuf, MAX_PATH, FindData, SLGP_RAWPATH);
    CheckTrue(Succeeded(HR), 'GetPath should succeed after direct SetPath');
    CheckTrue(SameText(APath, string(PathBuf)),
      'SetPath should store the path directly when hook is removed');
  end;

begin
  ShellLink := FShellLink as IShellLink;
  GShellLinkSetPathHits := 0;
  GShellLinkSetPathLastArg := '';
  GShellLinkSetPathNext := nil;
  try
    // first hook cycle
    CheckTrue(HookInterface(ShellLink, cShellLinkSetPathIndex,
      @HookTestShellLinkSetPathCallback, @GShellLinkSetPathNext));
    AssertHookedSetPath(cHookCycleInput1);
    HitsAfterFirstHook := GShellLinkSetPathHits;
    CheckTrue(UnHookInterface(@GShellLinkSetPathNext));
    GShellLinkSetPathNext := nil;

    // after first unhook: direct call, hit count unchanged
    AssertDirectSetPath(cDirectAfterUnhook1);
    CheckEquals(HitsAfterFirstHook, GShellLinkSetPathHits,
      'Unhooked SetPath should not invoke hook callback');

    // second hook cycle
    GShellLinkSetPathHits := 0;
    GShellLinkSetPathLastArg := '';
    CheckTrue(HookInterface(ShellLink, cShellLinkSetPathIndex,
      @HookTestShellLinkSetPathCallback, @GShellLinkSetPathNext));
    AssertHookedSetPath(cHookCycleInput2);
    HitsAfterSecondHook := GShellLinkSetPathHits;
    CheckTrue(UnHookInterface(@GShellLinkSetPathNext));
    GShellLinkSetPathNext := nil;

    // after second unhook: direct call again
    AssertDirectSetPath(cDirectAfterUnhook2);
    CheckEquals(HitsAfterSecondHook, GShellLinkSetPathHits,
      'Hook callback should stay inactive after second unhook');
  finally
    if Assigned(GShellLinkSetPathNext) then
      CheckTrue(UnHookInterface(@GShellLinkSetPathNext));
    GShellLinkSetPathNext := nil;
  end;
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2026.06.14
//功能：nil 跳板时 UnHookInterface 应返回 False
//参数：
////////////////////////////////////////////////////////////////////////////////
procedure THookIntfsTest.TestUnHookInterfaceNil;
var
  P: Pointer;
begin
  P := nil;
  CheckFalse(UnHookInterface(P));
end;

////////////////////////////////////////////////////////////////////////////////
//设计：Lsuper 2018.12.25
//功能：Register any test cases with the test runner
//参数：
////////////////////////////////////////////////////////////////////////////////
initialization
  RegisterTest(THookIntfsTest.Suite);

end.
