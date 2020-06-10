module Domain.Index exposing (Msg, Model, update, view, init)

import Browser.Navigation as Nav

import Json.Encode as Encode
import Json.Decode.Pipeline as JP
import Json.Decode as Decode
import Json.Decode exposing (Decoder, map3, field, string, int, at, list, maybe)

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)

import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col
import Bootstrap.Form as Form
import Bootstrap.Form.Fieldset as Fieldset
import Bootstrap.Form.Input as Input
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Button as Button
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.Utilities.Spacing as Spacing

import Url
import Http

import Bcc
import Bcc.Index
import Domain
import Route

-- MODEL

type alias Domain =
  { id: Domain.DomainId
  , name: String
  , vision: String }

type alias Model =
  { navKey : Nav.Key
  , baseUrl : String
  , newDomainName: String
  , domains: List Domain
   }

init: String -> Nav.Key -> (Model, Cmd Msg)
init baseUrl key =
  ( { navKey = key
    , baseUrl = baseUrl
    , newDomainName = ""
    , domains = [] }
  , loadAll baseUrl )

-- UPDATE

type Msg
  = Loaded (Result Http.Error (List Domain))
  | SetDomainName String
  | CreateDomain
  | DomainCreated (Result Http.Error Domain)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Loaded (Ok items) ->
      ({ model | domains = items }, Cmd.none)
    SetDomainName name ->
      ({ model | newDomainName = name}, Cmd.none)
    CreateDomain ->
      (model, createNewDomain model)
    DomainCreated (Ok item) ->
        (model, Route.pushUrl (Route.Domain item.id) model.navKey)
    _ ->
        Debug.log ("Domain.Index: " ++ Debug.toString msg ++ " " ++ Debug.toString model)
        (model, Cmd.none)

-- VIEW

createWithName : String -> Html Msg
createWithName name =
    Form.form [Html.Events.onSubmit CreateDomain]
        [ InputGroup.config (
              InputGroup.text
                [ Input.id name
                , Input.value name
                , Input.onInput SetDomainName
                , Input.placeholder "Name of the domain"
                ]
              )
              |> InputGroup.successors
                [ InputGroup.button
                  [ Button.attrs
                    [ Html.Attributes.type_ "submit"]
                    , Button.primary
                    , Button.disabled (name |> Bcc.ifNameValid (\_ -> True) (\_ -> False))
                    ]
                  [ text "Create new domain"]
                ]
              |> InputGroup.view
             ]



viewExisting : List Domain  -> Html Msg
viewExisting items =
    if List.isEmpty items then
        Html.p
            [ class "lead" ]
            [ text "No existing domains found - do you want to create one?" ]
    else
        let
            renderCard item =
                Card.config []
                    |> Card.block []
                        ( List.concat
                        [
                            [ Block.titleH4 [] [ text item.name ]]
                            , if String.length item.vision > 0
                                then [ Block.text [] [ text item.vision  ] ]
                                else []
                        ] )
                    |> Card.block []
                        [ Block.link
                            [ href (Route.routeToString (Route.Domain item.id)), class "stretched-link" ]
                            [text "View Domain"]
                        ]
        in
        Card.deck (items |> List.map renderCard)

view : Model -> Html Msg
view model =
  Grid.container []
    [ Grid.row [ Row.attrs [ Spacing.pt3 ] ]
      [ Grid.col [] [viewExisting model.domains] ]
    , Grid.row [ Row.attrs [Spacing.mt3]]
      [ Grid.col [] [ createWithName model.newDomainName ] ]
    ]

-- helpers

loadAll: String -> Cmd Msg
loadAll baseUrl =
  Http.get
    { url = baseUrl ++ "/api/domains"
    , expect = Http.expectJson Loaded domainsDecoder
    }


createNewDomain : Model -> Cmd Msg
createNewDomain model =
    let
        body =
            Encode.object
            [ ("name", Encode.string model.newDomainName) ]
    in
        Http.post
        { url = model.baseUrl ++ "/api/domains"
        , body = Http.jsonBody body
        , expect = Http.expectJson DomainCreated domainDecoder
        }


domainsDecoder: Decoder (List Domain)
domainsDecoder =
  Json.Decode.list domainDecoder


domainDecoder: Decoder Domain
domainDecoder =
  Decode.succeed Domain
    |> JP.required "id" Domain.idDecoder
    |> JP.required "name" Decode.string
    |> JP.optional "vision" Decode.string ""