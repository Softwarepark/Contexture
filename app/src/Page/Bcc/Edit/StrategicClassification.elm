module Page.Bcc.Edit.StrategicClassification exposing (..)

import Html exposing (Html, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onSubmit)

import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col
import Bootstrap.Form as Form
import Bootstrap.Form.Radio as Radio
import Bootstrap.Form.Checkbox as Checkbox
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.Button as Button
import Bootstrap.Text as Text
import Bootstrap.Utilities.Spacing as Spacing
import Bootstrap.Utilities.Display as Display

import Api
import BoundedContext.BoundedContextId exposing(BoundedContextId)
import BoundedContext.StrategicClassification as StrategicClassification

type alias Model = StrategicClassification.StrategicClassification


init : Api.Configuration -> BoundedContextId -> Model -> (Model, Cmd Msg)
init configuration id model =
    (model, Cmd.none)

type Action t
  = Add t
  | Remove t


type Msg
  = SetDomainType StrategicClassification.DomainType
  | ChangeBusinessModel (Action StrategicClassification.BusinessModel)
  | SetEvolution StrategicClassification.Evolution


noCommand model = (model, Cmd.none)

update : Msg -> Model -> (Model, Cmd Msg)
update msg classification =
  case msg of
    SetDomainType class ->
      noCommand { classification | domain = Just class}

    ChangeBusinessModel (Add business) ->
      noCommand { classification | business = business :: classification.business}

    ChangeBusinessModel (Remove business) ->
      noCommand { classification | business = classification.business |> List.filter (\bm -> bm /= business )}

    SetEvolution evo ->
      noCommand { classification | evolution = Just evo}

view : StrategicClassification.StrategicClassification -> Html Msg
view model =
  let
    domainDescriptions =
      [ StrategicClassification.Core, StrategicClassification.Supporting, StrategicClassification.Generic ]
      |> List.map StrategicClassification.domainDescription
      |> List.map (\d -> (d.name, d.description))
    businessDescriptions =
      [ StrategicClassification.Revenue, StrategicClassification.Engagement, StrategicClassification.Compliance, StrategicClassification.CostReduction ]
      |> List.map StrategicClassification.businessDescription
      |> List.map (\d -> (d.name, d.description))
    evolutionDescriptions =
      [ StrategicClassification.Genesis, StrategicClassification.CustomBuilt, StrategicClassification.Product, StrategicClassification.Commodity ]
      |> List.map StrategicClassification.evolutionDescription
      |> List.map (\d -> (d.name, d.description))
  in
  Form.group []
    [ Grid.row []
      [ Grid.col [] [ viewCaption "" "Strategic Classification"]]
    , Grid.row []
      [ Grid.col []
        [ viewLabel "classification" "Domain"
        , div []
            ( Radio.radioList "classification"
              [ viewRadioButton "core" model.domain StrategicClassification.Core SetDomainType StrategicClassification.domainDescription
              , viewRadioButton "supporting" model.domain StrategicClassification.Supporting SetDomainType StrategicClassification.domainDescription
              , viewRadioButton "generic" model.domain StrategicClassification.Generic SetDomainType StrategicClassification.domainDescription
              -- TODO: Other
              ]
            )
          , viewDescriptionList domainDescriptions Nothing
            |> viewInfoTooltip "How important is this context to the success of your organisation?"
          ]
        , Grid.col []
          [ viewLabel "businessModel" "Business Model"
          , div []
              [ viewCheckbox "revenue" StrategicClassification.businessDescription StrategicClassification.Revenue model.business
              , viewCheckbox "engagement" StrategicClassification.businessDescription StrategicClassification.Engagement model.business
              , viewCheckbox "Compliance" StrategicClassification.businessDescription StrategicClassification.Compliance model.business
              , viewCheckbox "costReduction" StrategicClassification.businessDescription StrategicClassification.CostReduction model.business
              -- TODO: Other
              ]
              |> Html.map ChangeBusinessModel

          , viewDescriptionList businessDescriptions Nothing
            |> viewInfoTooltip "What role does the context play in your business model?"
          ]
        , Grid.col []
          [ viewLabel "evolution" "Evolution"
          , div []
              ( Radio.radioList "evolution"
                [ viewRadioButton "genesis" model.evolution StrategicClassification.Genesis SetEvolution StrategicClassification.evolutionDescription
                , viewRadioButton "customBuilt" model.evolution StrategicClassification.CustomBuilt SetEvolution StrategicClassification.evolutionDescription
                , viewRadioButton "product" model.evolution StrategicClassification.Product SetEvolution StrategicClassification.evolutionDescription
                , viewRadioButton "commodity" model.evolution StrategicClassification.Commodity SetEvolution StrategicClassification.evolutionDescription
                -- TODO: Other
                ]
              )
            , viewDescriptionList evolutionDescriptions Nothing
            |> viewInfoTooltip "How evolved is the concept (see Wardley Maps)"
          ]
      ]
    ]



viewCaption : String -> String -> Html msg
viewCaption labelId caption =
  Form.label
    [ for labelId
    , Display.block
    , style "background-color" "lightGrey"
    , Spacing.p2
    ]
    [ text caption ]

viewRadioButton : String  -> Maybe value -> value -> (value -> m) -> (value -> StrategicClassification.Description) -> Radio.Radio m
viewRadioButton id currentValue option toMsg toTitle =
  Radio.createAdvanced
    [ Radio.id id, Radio.onClick (toMsg option), Radio.checked (currentValue == Just option) ]
    (Radio.label [] [ text (toTitle option).name ])

viewCheckbox : String -> (value -> StrategicClassification.Description) -> value -> List value -> Html (Action value)
viewCheckbox id description value currentValues =
  Checkbox.checkbox
    [Checkbox.id id
    , Checkbox.onCheck(\isChecked -> if isChecked then Add value else Remove value )
    , Checkbox.checked (List.member value currentValues)
    ]
    (description value).name


viewLabel : String -> String -> Html msg
viewLabel labelId caption =
  Form.label
    [ for labelId ]
    [ Html.b [] [ text caption ] ]

viewInfoTooltip : String -> Html msg -> Html msg
viewInfoTooltip title description =
  Form.help []
    [ Html.details []
      [ Html.summary []
        [ text title ]
      , Html.p [ ] [ description ]
      ]
    ]



viewDescriptionList : List (String, String) -> Maybe String -> Html msg
viewDescriptionList model sourceReference =
  let
    footer =
      case sourceReference of
        Just reference ->
          [ Html.footer
            [ class "blockquote-footer"]
            [ Html.a
              [target "_blank"
              , href reference
              ]
              [ text "Source of the descriptions"]
            ]
          ]
        Nothing -> []
  in
    Html.dl []
      ( model
        |> List.concatMap (
          \(t, d) ->
            [ Html.dt [] [ text t ]
            , Html.dd [] [ text d ]
            ]
        )
      )
    :: footer
    |> div []