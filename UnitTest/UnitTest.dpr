{ *********************************************************************** }
{                                                                         }
{   DelphiHookUtils 项目单元测试                                          }
{                                                                         }
{   设计：Lsuper 2026.06.01                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   Copyright (c) 1998-2026 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }

program UnitTest;

{$DEFINE CONSOLE_TESTRUNNER}

{$IFDEF CONSOLE_TESTRUNNER}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,

  TestFramework,
  TextTestRunner,
  GuiTestRunner,

  HookIntfsTests in 'HookIntfsTests.pas',
  HookUtilsTests in 'HookUtilsTests.pas';

begin
  if FindCmdLineSwitch('c') or FindCmdLineSwitch('console') then
  begin
    // NOTE:
    // UnitTest is built as a console application (see UnitTest.dproj <AppType>Console</AppType>).
    // When running from PowerShell/Cmd with output redirection, calling AttachConsole/AllocConsole
    // can detach stdout/stderr from the parent process and make console output disappear.
    // Keep the existing console/std handles so TextTestRunner output is visible and redirectable.
    with TextTestRunner.RunRegisteredTests do
      Free;
    if DebugHook <> 0 then
      Readln;
  end
  else begin
    ReportMemoryLeaksOnShutdown := True;
    GuiTestRunner.RunRegisteredTests;
  end;
end.
