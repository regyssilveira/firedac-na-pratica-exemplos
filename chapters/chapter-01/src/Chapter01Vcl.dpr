program Chapter01Vcl;

uses
  Vcl.Forms,
  Chapter01.MainForm in 'Chapter01.MainForm.pas' {MainForm};

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
