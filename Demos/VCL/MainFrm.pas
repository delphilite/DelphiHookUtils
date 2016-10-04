unit MainFrm;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type

  TMainForm = class(TForm)
    cbHookAPI: TCheckBox;
    cbHookCOM: TCheckBox;
    cbHookObject: TCheckBox;
    procedure cbHookAPIClick(Sender: TObject);
    procedure cbHookCOMClick(Sender: TObject);
    procedure cbHookObjectClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
  public

  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

uses
  ComObj, ShlObj, HookIntfs, HookUtils;

var
  MessageBoxNext: function (hWnd: HWND; lpText, lpCaption: PChar; uType: UINT): Integer; stdcall;

function MessageBoxCallBack(hWnd: HWND; lpText, lpCaption: PChar; uType: UINT): Integer; stdcall;
var
  S: string;
begin
  if Copy(lpText, 1, 5) = 'hello' then
    S := '我把 hello 开头的文字改成现在的样子了'
  else S := lpText;
  Result := MessageBoxNext(hWnd, PChar(S), lpCaption, uType);
end;

var
  ShellLink: IShellLink;
  ShellLinkSetPathNext: function(Self: IShellLink; pszFile: LPTSTR): HResult; stdcall;

function ShellLinkSetPathCallBack(Self: IShellLink; pszFile: LPTSTR): HResult; stdcall;
begin
  ShowMessage(Format('你调用到 ISHellLink($%x) 的 SetPath 方法了，参数 "%s"',
    [NativeInt(Pointer(Self)), string(pszFile)]));
  Result := ShellLinkSetPathNext(Self, 'd:\Windows');
end;

var
  ObjectFreeInstanceNext: procedure(Self: TObject);

procedure ObjectFreeInstanceCallBack(Self: TObject);
begin
  if Self <> nil then
    OutputDebugString(PChar(Format('"%s" 实例 [%x] 被释放!', [Self.ClassName,
      NativeInt(Self)])));
  ObjectFreeInstanceNext(Self);
end;

{ TMainForm }

procedure TMainForm.cbHookAPIClick(Sender: TObject);
const
{$IFDEF UNICODE}
  MessageBoxProcName = 'MessageBoxW';
{$ELSE}
  MessageBoxProcName = 'MessageBoxA';
{$ENDIF}
begin
  if TCheckBox(Sender).Checked then
  begin
    // 测试API钩子,MessageBox,因为我是Unicode版本Delphi
    if not Assigned(MessageBoxNext) then
    begin
      // 重绘,画出来的文字就会变样了.
      HookProc(user32, MessageBoxProcName, @MessageBoxCallBack, @MessageBoxNext);
    end
    else
    begin
      ShowMessage('钩过了');
    end;
  end
  else
  begin
    if Assigned(MessageBoxNext) then
      UnhookProc(@MessageBoxNext);
    @MessageBoxNext := nil;
  end;
  // 触发 MessageBox API 调用
  MessageBox(Handle, 'hello world!', '', 0);
end;

procedure TMainForm.cbHookCOMClick(Sender: TObject);
begin
  if TCheckBox(Sender).Checked then
  begin
    if not Assigned(ShellLinkSetPathNext) then
    begin
      HookInterface(ShellLink, 20, @ShellLinkSetPathCallBack, @ShellLinkSetPathNext);
      ShellLink.SetPath('c:\Windows');
    end
    else
    begin
      ShowMessage('钩过了');
    end;
  end
  else
  begin
    if Assigned(ShellLinkSetPathNext) then
      UnhookProc(@ShellLinkSetPathNext);
    @ShellLinkSetPathNext := nil;
  end;
end;

procedure TMainForm.cbHookObjectClick(Sender: TObject);
begin
  if TCheckBox(Sender).Checked then
  begin
    if not Assigned(ObjectFreeInstanceNext) then
    begin
      HookProc(@TObject.FreeInstance, @ObjectFreeInstanceCallBack, @ObjectFreeInstanceNext);
      ShowMessage('在你的 EventLog 窗口里看看有哪些对象被释放了 :-)');
    end
    else
    begin
      ShowMessage('钩过了');
    end;
  end
  else
  begin
    if Assigned(ObjectFreeInstanceNext) then
      UnhookProc(@ObjectFreeInstanceNext);
    @ObjectFreeInstanceNext := nil;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  ShellLink := CreateComObject(CLSID_ShellLink) as IShellLink;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  if Assigned(MessageBoxNext) then
    UnhookProc(@MessageBoxNext);
  if Assigned(ObjectFreeInstanceNext) then
    UnhookProc(@ObjectFreeInstanceNext);
  if Assigned(ShellLinkSetPathNext) then
    UnhookProc(@ShellLinkSetPathNext);
end;

end.
