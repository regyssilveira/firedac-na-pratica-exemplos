unit Chapter02.CatalogData;

interface

uses
  System.SysUtils,
  System.Classes,
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
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet;

type
  TCatalogData = class(TDataModule)
    Connection: TFDConnection;
    Products: TFDQuery;
    FBLink: TFDPhysFBDriverLink;
    SQLiteLink: TFDPhysSQLiteDriverLink;
  private
    function RequiredEnvironment(const AName: string): string;
  public
    procedure Configure;
    procedure OpenProducts;
  end;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

function TCatalogData.RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

procedure TCatalogData.Configure;
var
  Driver: string;
begin
  Driver := RequiredEnvironment('FIRESTORE_DRIVER');
  Connection.Close;
  Connection.Params.Clear;
  Connection.LoginPrompt := False;
  Connection.ResourceOptions.SilentMode := True;
  if SameText(Driver, 'SQLite') then
  begin
    Connection.Params.Values['DriverID'] := 'SQLite';
    Connection.Params.Values['Database'] := RequiredEnvironment('CH02_SQLITE_DATABASE');
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

procedure TCatalogData.OpenProducts;
begin
  if Connection.Params.Values['DriverID'] = '' then
    Configure;
  Connection.Open;
  Products.Close;
  Products.SQL.Text :=
    'SELECT id, sku, name, price FROM product ORDER BY name, id';
  Products.Open;
end;

end.
