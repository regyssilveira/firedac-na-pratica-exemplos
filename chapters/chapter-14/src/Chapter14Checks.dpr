program Chapter14Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.DatS,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure DefineCart(ATable: TFDMemTable);
begin
  ATable.FieldDefs.Add('item_id', ftLargeint, 0, True);
  ATable.FieldDefs.Add('product_id', ftLargeint, 0, True);
  ATable.FieldDefs.Add('sku', ftWideString, 40, True);
  ATable.FieldDefs.Add('name', ftWideString, 160, True);
  ATable.FieldDefs.Add('quantity', ftInteger, 0, True);
  with ATable.FieldDefs.AddFieldDef do
  begin
    Name := 'unit_price';
    DataType := ftFMTBcd;
    Precision := 18;
    Size := 2;
    Required := True;
  end;
  with ATable.FieldDefs.AddFieldDef do
  begin
    Name := 'line_total';
    DataType := ftFMTBcd;
    Precision := 18;
    Size := 2;
    Required := True;
  end;
  ATable.CreateDataSet;
  ATable.AddIndex('ux_item', 'item_id', '', [soUnique]);
  ATable.AddIndex('ix_product', 'product_id', '', []);
end;

procedure AddCartItem(ATable: TFDMemTable; AItemId, AProductId: Int64;
  const ASku, AName: string; AQuantity: Integer; AUnitPrice: Currency);
begin
  Check(AQuantity > 0, 'Quantidade deve ser positiva.');
  ATable.Append;
  try
    ATable.FieldByName('item_id').AsLargeInt := AItemId;
    ATable.FieldByName('product_id').AsLargeInt := AProductId;
    ATable.FieldByName('sku').AsString := ASku;
    ATable.FieldByName('name').AsString := AName;
    ATable.FieldByName('quantity').AsInteger := AQuantity;
    ATable.FieldByName('unit_price').AsCurrency := AUnitPrice;
    ATable.FieldByName('line_total').AsCurrency := AQuantity * AUnitPrice;
    ATable.Post;
  except
    ATable.Cancel;
    raise;
  end;
end;

procedure SeedCart(ATable: TFDMemTable);
begin
  AddCartItem(ATable, 1, 101, 'SKU-101', 'Teclado', 1, 199.90);
  AddCartItem(ATable, 2, 102, 'SKU-102', 'Mouse', 2, 89.50);
  AddCartItem(ATable, 3, 103, 'SKU-103', 'Caf' + #$00E9, 3, 35.75);
end;

procedure RunCreate;
var
  Cart: TFDMemTable;
  Total: Currency;
begin
  Cart := TFDMemTable.Create(nil);
  try
    DefineCart(Cart);
    SeedCart(Cart);
    Check(Cart.RecordCount = 3, 'Carrinho não contém três itens.');
    Cart.IndexName := 'ux_item';
    Check(Cart.FindKey([Int64(2)]), 'Índice único não localizou item 2.');
    Check(Cart.FieldByName('name').AsString = 'Mouse', 'Item indexado incorreto.');
    Total := 0;
    Cart.First;
    while not Cart.Eof do
    begin
      Total := Total + Cart.FieldByName('line_total').AsCurrency;
      Cart.Next;
    end;
    Check(Abs(Total - 486.15) < 0.001, 'Total do carrinho incorreto.');
    Writeln('EX-14-01 aprovado: schema, índice, validação e total conferidos.');
  finally
    Cart.Free;
  end;
end;

procedure RunCopy;
var
  Source, Snapshot: TFDMemTable;
begin
  Source := TFDMemTable.Create(nil);
  Snapshot := TFDMemTable.Create(nil);
  try
    DefineCart(Source);
    SeedCart(Source);
    Source.Filter := 'quantity > 1';
    Source.Filtered := True;
    Snapshot.CopyDataSet(Source, [coStructure, coRestart, coAppend]);
    Check(Snapshot.RecordCount = 2, 'CopyDataSet não respeitou a view filtrada.');
    Snapshot.First;
    Snapshot.Edit;
    Snapshot.FieldByName('name').AsString := 'Alterado na cópia';
    Snapshot.Post;
    Source.Filtered := False;
    Check(Source.Locate('item_id', Snapshot.FieldByName('item_id').AsLargeInt, []),
      'Item copiado não existe na origem.');
    Check(Source.FieldByName('name').AsString <> 'Alterado na cópia',
      'CopyDataSet compartilhou uma edição com a origem.');
    Check(Source.RecordCount = 3, 'A cópia alterou a contagem da origem.');
    Writeln('EX-14-02 aprovado: cópia seletiva possui armazenamento independente.');
  finally
    Snapshot.Free;
    Source.Free;
  end;
end;

procedure RunClone;
var
  Source, Clone, DataView: TFDMemTable;
begin
  Source := TFDMemTable.Create(nil);
  Clone := TFDMemTable.Create(nil);
  DataView := TFDMemTable.Create(nil);
  try
    DefineCart(Source);
    SeedCart(Source);
    Clone.CloneCursor(Source, False, False);
    Clone.Filter := 'quantity > 1';
    Clone.Filtered := True;
    Check(Clone.RecordCount = 2, 'Filtro próprio do clone não foi aplicado.');
    Check(Source.RecordCount = 3, 'Filtro do clone contaminou a view da origem.');
    Clone.First;
    Clone.Edit;
    Clone.FieldByName('name').AsString := 'Alterado pelo clone';
    Clone.Post;
    Check(Source.Locate('item_id', Clone.FieldByName('item_id').AsLargeInt, []),
      'Item do clone não foi localizado na origem.');
    Check(Source.FieldByName('name').AsString = 'Alterado pelo clone',
      'CloneCursor não compartilhou a alteração subjacente.');
    Clone.Close;
    Check(Source.Active and (Source.RecordCount = 3),
      'Fechar o clone invalidou a origem.');
    DataView.Data := Source.Data;
    Check(DataView.Locate('item_id', Int64(1), []),
      'View por Data não localizou o item compartilhado.');
    DataView.Edit;
    DataView.FieldByName('quantity').AsInteger := 4;
    DataView.Post;
    Check(Source.Locate('item_id', Int64(1), []), 'Origem perdeu o item 1.');
    Check(Source.FieldByName('quantity').AsInteger = 1,
      'Atribuição de Data compartilhou uma alteração inesperadamente.');
    Check(DataView.FieldByName('quantity').AsInteger = 4,
      'View criada por Data não preservou sua edição independente.');
    Writeln('EX-14-03 aprovado: CloneCursor compartilha; Data importa uma cópia.');
  finally
    DataView.Free;
    Clone.Free;
    Source.Free;
  end;
end;

procedure RunMasterDetail;
var
  Cart, Options: TFDMemTable;
  Source: TDataSource;
begin
  Cart := TFDMemTable.Create(nil);
  Options := TFDMemTable.Create(nil);
  Source := TDataSource.Create(nil);
  try
    DefineCart(Cart);
    SeedCart(Cart);
    Options.FieldDefs.Add('option_id', ftLargeint, 0, True);
    Options.FieldDefs.Add('cart_item_id', ftLargeint, 0, True);
    Options.FieldDefs.Add('description', ftWideString, 80, True);
    Options.CreateDataSet;
    Options.AppendRecord([1, 1, 'Garantia estendida']);
    Options.AppendRecord([2, 2, 'Embalagem para presente']);
    Options.AppendRecord([3, 2, 'Pilha adicional']);
    Options.IndexFieldNames := 'cart_item_id';
    Source.DataSet := Cart;
    Options.MasterSource := Source;
    Options.MasterFields := 'item_id';
    Options.DetailFields := 'cart_item_id';
    Check(Cart.Locate('item_id', Int64(1), []), 'Mestre 1 não localizado.');
    Check(Options.RecordCount = 1, 'Detalhes do item 1 incorretos.');
    Check(Cart.Locate('item_id', Int64(2), []), 'Mestre 2 não localizado.');
    Check(Options.RecordCount = 2, 'Detalhes do item 2 incorretos.');
    Check(Cart.Locate('item_id', Int64(3), []), 'Mestre 3 não localizado.');
    Check(Options.RecordCount = 0, 'Item sem detalhes exibiu órfãos.');
    Writeln('EX-14-04 aprovado: range mestre-detalhe local conferido.');
  finally
    Source.Free;
    Options.Free;
    Cart.Free;
  end;
end;

procedure RunNested;
var
  Orders: TFDMemTable;
  Items: TDataSet;
  ItemsDef: TFieldDef;
  ItemsField: TDataSetField;
begin
  Orders := TFDMemTable.Create(nil);
  try
    Orders.FieldDefs.Add('order_id', ftLargeint, 0, True);
    ItemsDef := Orders.FieldDefs.AddFieldDef;
    ItemsDef.Name := 'items';
    ItemsDef.DataType := ftDataSet;
    ItemsDef.ChildDefs.Add('product_id', ftLargeint, 0, True);
    ItemsDef.ChildDefs.Add('quantity', ftInteger, 0, True);
    ItemsDef.ChildDefs.Add('name', ftWideString, 80, True);
    Orders.CreateDataSet;
    Orders.AppendRecord([Int64(501), Null]);
    ItemsField := Orders.FieldByName('items') as TDataSetField;
    Items := ItemsField.NestedDataSet;
    Items.AppendRecord([Int64(101), 2, 'Teclado']);
    Items.AppendRecord([Int64(102), 1, 'Mouse']);
    Check(Items.RecordCount = 2, 'Dataset aninhado não preservou dois itens.');
    Items.First;
    Items.Edit;
    Items.FieldByName('quantity').AsInteger := 3;
    Items.Post;
    Check(Items.FieldByName('quantity').AsInteger = 3,
      'Edição do dataset aninhado não foi preservada.');
    Check(Orders.FieldByName('order_id').AsLargeInt = 501,
      'Identidade do registro pai foi alterada.');
    Writeln('EX-14-05 aprovado: schema e edição do dataset aninhado conferidos.');
  finally
    Orders.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter14Checks create|copy|clone|master-detail|nested');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'create') then RunCreate
    else if SameText(ParamStr(1), 'copy') then RunCopy
    else if SameText(ParamStr(1), 'clone') then RunClone
    else if SameText(ParamStr(1), 'master-detail') then RunMasterDetail
    else if SameText(ParamStr(1), 'nested') then RunNested
    else
    begin
      ShowUsage;
      ExitCode := 2;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
