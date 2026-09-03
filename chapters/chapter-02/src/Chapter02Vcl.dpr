program Chapter02Vcl;

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  Chapter02.CatalogData in 'Chapter02.CatalogData.pas' {CatalogData: TDataModule},
  Chapter02.Forms in 'Chapter02.Forms.pas';

var
  Catalog: TCatalogData;
  ProductsForm: TProductsForm;
  StatusForm: TCatalogStatusForm;
  ResultFile: string;

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Catalog := TCatalogData.Create(nil);
  ProductsForm := nil;
  StatusForm := nil;
  try
    try
      Catalog.Configure;
      Catalog.OpenProducts;
      ProductsForm := TProductsForm.CreateWithCatalog(nil, Catalog);
      StatusForm := TCatalogStatusForm.CreateWithCatalog(nil, Catalog);

      if ProductsForm.Source.DataSet <> Catalog.Products then
        raise Exception.Create('O formulário de produtos não usa o dataset compartilhado.');
      if StatusForm.Source.DataSet <> Catalog.Products then
        raise Exception.Create('O formulário de estado não usa o dataset compartilhado.');

      if GetEnvironmentVariable('CH02_AUTORUN') = '1' then
      begin
        ResultFile := GetEnvironmentVariable('CH02_AUTORUN_RESULT');
        if ResultFile <> '' then
          TFile.WriteAllText(ResultFile, 'OK', TEncoding.UTF8);
      end
      else
      begin
        ProductsForm.Show;
        StatusForm.Show;
        Application.Run;
      end;
    except
      on E: Exception do
      begin
        ExitCode := 1;
        ResultFile := GetEnvironmentVariable('CH02_AUTORUN_RESULT');
        if ResultFile <> '' then
          TFile.WriteAllText(ResultFile, E.ClassName + ': ' + E.Message,
            TEncoding.UTF8);
      end;
    end;
  finally
    StatusForm.Free;
    ProductsForm.Free;
    Catalog.Free;
  end;
end.
