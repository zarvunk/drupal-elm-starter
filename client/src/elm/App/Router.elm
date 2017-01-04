module App.Router exposing (delta2url, location2messages)

import App.Model exposing (..)
import App.PageType exposing (..)
import Navigation exposing (Location)
import RouteUrl exposing (HistoryEntry(..), UrlChange)
import UrlParser exposing (Parser, map, parseHash, s, oneOf, (</>), int, string)


delta2url : Model -> Model -> Maybe UrlChange
delta2url previous current =
    case current.activePage of
        AccessDenied ->
            Nothing

        Login ->
            Just <| UrlChange NewEntry "/#login"

        MyAccount ->
            Just <| UrlChange NewEntry "/#my-account"

        PageNotFound ->
            Just <| UrlChange NewEntry "/#404"

        PageSensor id ->
            Just <| UrlChange NewEntry ("#sensor/" ++ id)

        Sensors ->
            Just <| UrlChange NewEntry "#"


location2messages : Location -> List Msg
location2messages location =
    case UrlParser.parseHash parseUrl location of
        Just msgs ->
            [ msgs ]

        Nothing ->
            []


parseUrl : Parser (Msg -> c) c
parseUrl =
    oneOf
        [ map (SetActivePage Sensors) (s "")
        , map (\id -> SetActivePage <| PageSensor (toString id)) (s "sensor" </> int)
        , map (SetActivePage Login) (s "login")
        , map (SetActivePage MyAccount) (s "my-account")
        ]