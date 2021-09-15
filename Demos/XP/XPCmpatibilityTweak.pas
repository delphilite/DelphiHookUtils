{ *********************************************************************** }
{                                                                         }
{   Delphi 11 Windows XP compatibility tweak Thread TickCount Fix 单元    }
{                                                                         }
{   设计：Lsuper 2021.09.15                                               }
{   备注：                                                                }
{   审核：                                                                }
{                                                                         }
{   See: http://bbs.2ccc.com/topic.asp?topicid=617636                     }
{        http://bbs.2ccc.com/topic.asp?topicid=617767                     }
{                                                                         }
{   Copyright (c) 1998-2021 Super Studio                                  }
{                                                                         }
{ *********************************************************************** }

unit XPCmpatibilityTweak;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

implementation

uses
  Winapi.Windows, System.SysUtils, HookUtils;

var
  GetTickCount64Next: function : UInt64; stdcall;

function GetTickCount64CallBack: UInt64; stdcall;
begin
  if TOSVersion.Major < 6 then
    Result := Winapi.Windows.GetTickCount
  else Result := GetTickCount64Next;
end;

initialization
  HookProc(@Winapi.Windows.GetTickCount64, @GetTickCount64CallBack, @GetTickCount64Next);

finalization
  UnHookProc(@GetTickCount64Next);

end.
