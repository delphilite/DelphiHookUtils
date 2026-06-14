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
  System.SysUtils, TestFramework, HookIntfs;

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
    procedure TestUnHookInterfaceNil;
  end;

implementation

uses
  Winapi.ActiveX, Winapi.ShlObj, Winapi.Windows,
  System.Win.ComObj;

const
  cShellLinkSetPathIndex = 20;
  cHookRedirectPath = 'C:\Windows';

var
  GShellLinkSetPathHits: Integer;
  GShellLinkSetPathLastArg: string;
  GShellLinkSetPathNext: function(Self: IShellLink; pszFile: PChar): HResult; stdcall;

////////////////////////////////////////////////////////////////////////////////
//设计：Linc 2026.06.14
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
//设计：Linc 2026.06.14
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
//设计：Linc 2026.06.14
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
//设计：Linc 2026.06.14
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
//设计：Linc 2026.06.14
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
