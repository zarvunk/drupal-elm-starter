port module App.Update exposing (init, update, subscriptions)

import App.Model exposing (..)
import App.PageType exposing (Page(..))
import Config
import Date
import Dict
import Http
import ItemManager.Model
import ItemManager.Update
import Json.Decode exposing (bool, decodeValue)
import Json.Encode exposing (Value)
import Pages.Login.Update
import Pusher.Model
import Pusher.Utils exposing (getClusterName)
import RemoteData exposing (RemoteData(..), WebData)
import Task
import Time exposing (minute)
import User.Model exposing (..)


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        user =
            NotAsked

        ( config, cmds, activePage ) =
            case (Dict.get flags.hostname Config.configs) of
                Just config ->
                    let
                        defaultCmds =
                            [ pusherKey
                                ( config.pusherKey.key
                                , getClusterName config.pusherKey.cluster
                                , Pusher.Model.eventNames
                                )
                            , Task.perform SetCurrentDate Date.now
                            ]

                        ( cmds, activePage_ ) =
                            if (String.isEmpty flags.accessToken) then
                                -- Check if we have already an access token.
                                ( defaultCmds, Login )
                            else
                                ( [ Cmd.map PageLogin <| Pages.Login.Update.fetchUserFromBackend config.backendUrl flags.accessToken ] ++ defaultCmds
                                , emptyModel.activePage
                                )
                    in
                        ( Success config
                        , cmds
                        , activePage_
                        )

                Nothing ->
                    ( Failure "No config found"
                    , [ Cmd.none ]
                    , emptyModel.activePage
                    )
    in
        ( { emptyModel
            | accessToken = flags.accessToken
            , activePage = activePage
            , config = config
            , user = user
          }
        , Cmd.batch cmds
        )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        backendUrl =
            case model.config of
                Success config ->
                    config.backendUrl

                _ ->
                    ""
    in
        case msg of
            HandleOfflineEvent (Ok offline) ->
                { model | offline = offline } ! []

            HandleOfflineEvent (Err err) ->
                model ! []

            Logout ->
                ( { emptyModel
                    | accessToken = ""
                    , activePage = Login
                    , config = model.config
                  }
                , accessTokenPort ""
                )

            MsgItemManager subMsg ->
                case model.user of
                    Success user ->
                        let
                            ( val, cmds, redirectPage ) =
                                ItemManager.Update.update model.currentDate backendUrl model.accessToken user subMsg model.pageItem

                            modelUpdated =
                                { model | pageItem = val }

                            ( modelUpdatedWithSetPage, setPageCmds ) =
                                Maybe.map
                                    (\page ->
                                        update (SetActivePage page) modelUpdated
                                    )
                                    redirectPage
                                    |> Maybe.withDefault ( modelUpdated, Cmd.none )
                        in
                            ( modelUpdatedWithSetPage
                            , Cmd.batch
                                [ Cmd.map MsgItemManager cmds
                                , setPageCmds
                                ]
                            )

                    _ ->
                        -- If we don't have a user, we have nothing to do.
                        model ! []

            PageLogin msg ->
                let
                    ( val, cmds, ( webDataUser, accessToken ) ) =
                        Pages.Login.Update.update backendUrl msg model.pageLogin

                    modelUpdated =
                        { model
                            | pageLogin = val
                            , accessToken = accessToken
                            , user = webDataUser
                        }

                    ( modelWithRedirect, setActivePageCmds ) =
                        case webDataUser of
                            -- If user was successfuly fetched, reditect to my
                            -- account page.
                            Success _ ->
                                let
                                    nextPage =
                                        case modelUpdated.activePage of
                                            Login ->
                                                -- Redirect to the dashboard.
                                                Dashboard

                                            _ ->
                                                -- Keep the active page.
                                                modelUpdated.activePage
                                in
                                    update (SetActivePage nextPage) modelUpdated

                            Failure _ ->
                                -- Unset the wrong access token.
                                update (SetActivePage Login) { modelUpdated | accessToken = "" }

                            _ ->
                                modelUpdated ! []
                in
                    ( modelWithRedirect
                    , Cmd.batch
                        [ Cmd.map PageLogin cmds
                        , accessTokenPort accessToken
                        , setActivePageCmds
                        ]
                    )

            SetActivePage page ->
                let
                    activePage =
                        setActivePageAccess model.user page

                    ( modelUpdated, command ) =
                        -- For a few, we also delegate some initialization
                        case activePage of
                            Dashboard ->
                                -- If we're showing a `Items` page, make sure we `Subscribe`
                                update (MsgItemManager ItemManager.Model.FetchAll) model

                            Item id ->
                                -- If we're showing a `Item`, make sure we `Subscribe`
                                update (MsgItemManager (ItemManager.Model.Subscribe id)) model

                            _ ->
                                ( model, Cmd.none )
                in
                    -- Close the sidebar in case it was opened.
                    ( { modelUpdated
                        | activePage = setActivePageAccess model.user activePage
                        , sidebarOpen = False
                      }
                    , command
                    )

            SetCurrentDate date ->
                { model | currentDate = date } ! []

            Tick _ ->
                model ! [ Task.perform SetCurrentDate Date.now ]

            ToggleSideBar ->
                { model | sidebarOpen = not model.sidebarOpen } ! []


{-| Determine is a page can be accessed by a user (anonymous or authenticated),
and if not return a access denied page.

If the user is authenticated, don't allow them to revisit Login page. Do the
opposite for anonymous user - don't allow them to visit the MyAccount page.
-}
setActivePageAccess : WebData User -> Page -> Page
setActivePageAccess user page =
    case user of
        Success _ ->
            if page == Login then
                AccessDenied
            else
                page

        Failure _ ->
            if page == Login then
                page
            else if page == PageNotFound then
                page
            else
                AccessDenied

        _ ->
            page


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map MsgItemManager <| ItemManager.Update.subscriptions model.pageItem model.activePage
        , Time.every minute Tick
        , offline (decodeValue bool >> HandleOfflineEvent)
        ]


{-| Send access token to JS.
-}
port accessTokenPort : String -> Cmd msg


{-| Send Pusher key and cluster to JS.
-}
port pusherKey : ( String, String, List String ) -> Cmd msg


{-| Get a singal if internet connection is lost.
-}
port offline : (Value -> msg) -> Sub msg
