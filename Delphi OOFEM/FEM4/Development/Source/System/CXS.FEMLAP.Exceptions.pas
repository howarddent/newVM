unit CXS.FEMLAP.Exceptions;

{$mode delphi}{$H+}

interface

uses SysUtils;


type ELibException = class(Exception)

  type NErrorType = (erIndexOutOfBounds, erWrongSizedArray, erNotImplementedFeature);

  private
    FError : NErrorType;

  public
    	property Error : NErrorType read FError write FError;
end;

implementation

end.
