unit MainFrm;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, SHDocVw;

type
  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FWebBrowser: TWebBrowser;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  LoadLibrary('Dll.dll');
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  FWebBrowser := TWebBrowser.Create(Self);
  TWinControl(FWebBrowser).Parent := Self;
  FWebBrowser.Align := alClient;
  FWebBrowser.Navigate('www.baidu.com');
end;

end.
