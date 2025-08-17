{ ***************************************************** }
{                                                       }
{  Pascal language binding for the Capstone engine      }
{                                                       }
{  Unit Name: Demo                                      }
{     Author: Lsuper 2024.05.01                         }
{    Purpose: Demo                                      }
{    License: Mozilla Public License 2.0                }
{                                                       }
{  Copyright (c) 1998-2024 Super Studio                 }
{                                                       }
{ ***************************************************** }

program Demo;

{$IF CompilerVersion >= 21.0}
  {$WEAKLINKRTTI ON}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$IFEND}

{$APPTYPE CONSOLE}

{$R *.res}

uses
  SysUtils, HookUtils;

var
  ObjectFreeInstanceNext: procedure(Self: TObject);

procedure ObjectFreeInstanceCallBack(Self: TObject);
begin
  if Self <> nil then
    WriteLn(Format('ObjectFreeInstanceCallBack: %s, %x', [Self.ClassName, NativeInt(Self)]));
  ObjectFreeInstanceNext(Self);
end;

procedure RunFreeInstanceTest;
begin
  with TSimpleRWSync.Create do
  try
  finally
    Free;
  end;
  with EExternal.Create('') do
  try
  finally
    Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    WriteLn('Start, HookUtils ...');
    WriteLn('');
    HookProc(@TObject.FreeInstance, @ObjectFreeInstanceCallBack, @ObjectFreeInstanceNext);

    RunFreeInstanceTest; { do some test ... }

    UnhookProc(@ObjectFreeInstanceNext);
    @ObjectFreeInstanceNext := nil;

    WriteLn('');
    WriteLn('Done.');
  except
    on E: Exception do
      WriteLn(Format('Error HookUtils: %s', [E.Message]));
  end;
  ReadLn;
end.
