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
  System.SysUtils, TestFramework, HookUtils;

type
  THookUtilsTest = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHookProcFreeInstance;
    procedure TestHookProcGetTickCountByModule;
    procedure TestHookProcInvalidModule;
    procedure TestHookProcNilPointers;
    procedure TestUnHookNil;
  end;

implementation

uses
  Winapi.Windows, System.Classes;

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
