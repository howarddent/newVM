unit uPlaces;

{*******************************************************************************

     The CanterburyRain demo's locations: every populated place in the UK
     and Ireland with a population over 50,000 (GeoNames, CC-BY 4.0), and
     the outline of the United Kingdom, Ireland and the Isle of Man for
     the map (Natural Earth 1:50m, public domain). Both tables are
     generated into ukplaces.inc / ukoutline.inc by make_location_data.py
     (see that script for the sources and the filtering) and compiled in,
     so the list and the map need no network - only the weather does.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

type
  TPlace = record
    Name: string;
    Country: string;     // England, Scotland, Wales, Northern Ireland, Ireland
    Lat, Lon: Double;    // degrees
    Population: Integer; // GeoNames' figure
    East, North: Double; // British National Grid, m (for the county map)
  end;

{$I ukplaces.inc}
{$I ukoutline.inc}

const
  DefaultPlaceName = 'Canterbury';

// 'Canterbury, England' - the form used in titles and the dropdown.
function PlaceCaption(Index: Integer): string;
// Index of the place called Name (case-insensitive), or -1.
function FindPlace(const Name: string): Integer;

implementation

uses
  SysUtils;

function PlaceCaption(Index: Integer): string;
begin
  result := Places[Index].Name + ', ' + Places[Index].Country;
end;

function FindPlace(const Name: string): Integer;
var
  i: Integer;
begin
  for i := 0 to PlaceCount - 1 do
    if SameText(Places[i].Name, Name) then Exit(i);
  result := -1;
end;

end.
