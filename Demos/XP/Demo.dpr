program Demo;

{$IF CompilerVersion >= 21.0}
  {$WEAKLINKRTTI ON}
  {$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$IFEND}

uses
  System.SysUtils,

  HookUtils in '..\..\Source\HookUtils.pas',
  HookIntfs in '..\..\Source\HookIntfs.pas',

  XPCmpatibilityTweak in 'XPCmpatibilityTweak.pas',

  Vcl.Forms,

  MainFrm in 'MainFrm.pas' {MainForm};

{$R *.res}

{$SETPEOSVERSION 5.0}
{$SETPESUBSYSVERSION 5.0} { for Windows XP }

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
