unit MainFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, FMX.Types, FMX.Controls,
  FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation, FMX.StdCtrls;

type
  TMainForm = class(TForm)
    cbHookObject: TCheckBox;
    btnTestObject: TButton;
    procedure cbHookObjectClick(Sender: TObject);
    procedure btnTestObjectClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

uses
  HookIntfs, HookUtils;

var
  ObjectFreeInstanceNext: procedure(Self: TObject);

procedure ObjectFreeInstanceCallBack(Self: TObject);
begin
  if Self <> nil then
    Log.d('"%s" 实例 [%x] 被释放!', [Self.ClassName, NativeInt(Self)]);
  ObjectFreeInstanceNext(Self);
end;

{ TMainForm }

procedure TMainForm.btnTestObjectClick(Sender: TObject);
begin
  TButton.Create(nil).Free;
end;

procedure TMainForm.cbHookObjectClick(Sender: TObject);
begin
  if not TCheckBox(Sender).IsChecked then
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

end.
