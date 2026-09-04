unit Chapter01.MainForm;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Data.DB,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.DBGrids,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet;

type
  TMainForm = class(TForm)
    Connection: TFDConnection;
    QryProducts: TFDQuery;
    DsProducts: TDataSource;
    GridProducts: TDBGrid;
    BtnOpen: TButton;
    EdtSku: TEdit;
    BtnFind: TButton;
    LblStatus: TLabel;
    FBLink: TFDPhysFBDriverLink;
    SQLiteLink: TFDPhysSQLiteDriverLink;
    procedure BtnFindClick(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    function RequiredEnvironment(const AName: string): string;
    procedure ConfigureConnection;
    procedure OpenCatalog;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

function TMainForm.RequiredEnvironment(const AName: string): string;
begin
  var Value := GetEnvironmentVariable(AName);
  if Value = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
  Result := Value;
end;

procedure TMainForm.ConfigureConnection;
begin
  var Driver := RequiredEnvironment('FIRESTORE_DRIVER');
  Connection.Close;
  Connection.Params.Clear;
  Connection.LoginPrompt := False;
  if SameText(Driver, 'SQLite') then
  begin
    Connection.Params.Values['DriverID'] := 'SQLite';
    Connection.Params.Values['Database'] := RequiredEnvironment('CH01_SQLITE_DATABASE');
    Connection.Params.Values['OpenMode'] := 'Open';
    Connection.Params.Values['ForeignKeys'] := 'On';
  end
  else if SameText(Driver, 'FB') then
  begin
    FBLink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
    Connection.Params.Values['DriverID'] := 'FB';
    Connection.Params.Values['Protocol'] := 'TCPIP';
    Connection.Params.Values['Server'] := RequiredEnvironment('FIRESTORE_DB_HOST');
    Connection.Params.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
    Connection.Params.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
    Connection.Params.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
    Connection.Params.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
    Connection.Params.Values['CharacterSet'] := 'UTF8';
  end
  else
    raise Exception.CreateFmt('Driver não suportado: %s', [Driver]);
end;

procedure TMainForm.OpenCatalog;
begin
  ConfigureConnection;
  try
    Connection.Open;
    QryProducts.Close;
    QryProducts.SQL.Text := '''
      SELECT id, sku, name, price
      FROM product
      ORDER BY name, id
      ''';
    QryProducts.Open;
    LblStatus.Caption := Format('%d produto(s).', [QryProducts.RecordCount]);
  except
    on E: EFDDBEngineException do
      raise Exception.CreateFmt('Não foi possível abrir o catálogo. %s', [E.Message]);
  end;
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  OpenCatalog;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if GetEnvironmentVariable('CH01_AUTORUN') <> '1' then
    Exit;
  var ResultFile := GetEnvironmentVariable('CH01_AUTORUN_RESULT');
  try
    OpenCatalog;
    if QryProducts.IsEmpty then
      raise Exception.Create('O catálogo foi aberto sem produtos.');
    if ResultFile <> '' then
      TFile.WriteAllText(ResultFile, 'OK', TEncoding.UTF8);
  except
    on E: Exception do
    begin
      ExitCode := 1;
      if ResultFile <> '' then
        TFile.WriteAllText(ResultFile, E.ClassName + ': ' + E.Message,
          TEncoding.UTF8);
    end;
  end;
  Application.Terminate;
end;

procedure TMainForm.BtnFindClick(Sender: TObject);
begin
  if not Connection.Connected then
    ConfigureConnection;
  Connection.Open;
  QryProducts.Close;
  QryProducts.SQL.Text := '''
    SELECT id, sku, name, price
    FROM product
    WHERE sku = :sku
    ''';
  QryProducts.ParamByName('sku').AsString := EdtSku.Text;
  QryProducts.Open;
  LblStatus.Caption := Format('%d produto(s).', [QryProducts.RecordCount]);
end;

end.
