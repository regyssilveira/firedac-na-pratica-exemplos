unit Chapter02.Forms;

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.DBGrids,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  Chapter02.CatalogData;

type
  TProductsForm = class(TForm)
  private
    FSource: TDataSource;
    FGrid: TDBGrid;
  public
    constructor CreateWithCatalog(AOwner: TComponent; ACatalog: TCatalogData);
    property Source: TDataSource read FSource;
  end;

  TCatalogStatusForm = class(TForm)
  private
    FSource: TDataSource;
    FStatus: TLabel;
  public
    constructor CreateWithCatalog(AOwner: TComponent; ACatalog: TCatalogData);
    property Source: TDataSource read FSource;
  end;

implementation

constructor TProductsForm.CreateWithCatalog(AOwner: TComponent;
  ACatalog: TCatalogData);
begin
  inherited CreateNew(AOwner);
  Caption := 'Produtos';
  Width := 640;
  Height := 360;
  FSource := TDataSource.Create(Self);
  FSource.DataSet := ACatalog.Products;
  FGrid := TDBGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.DataSource := FSource;
end;

constructor TCatalogStatusForm.CreateWithCatalog(AOwner: TComponent;
  ACatalog: TCatalogData);
begin
  inherited CreateNew(AOwner);
  Caption := 'Estado do catálogo';
  Width := 320;
  Height := 140;
  FSource := TDataSource.Create(Self);
  FSource.DataSet := ACatalog.Products;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Left := 24;
  FStatus.Top := 32;
  FStatus.Caption := Format('%d produto(s) no dataset compartilhado.',
    [ACatalog.Products.RecordCount]);
end;

end.
