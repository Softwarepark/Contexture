module Page.Bcc.Edit.Dependencies exposing (
  Msg(..), Model,
  update, init, view)

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)

import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col
import Bootstrap.Form as Form
import Bootstrap.Form.Input as Input
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Form.Radio as Radio
import Bootstrap.Button as Button
import Bootstrap.ButtonGroup as ButtonGroup
import Bootstrap.Card.Block as Block
import Bootstrap.Card as Card
import Bootstrap.Modal as Modal
import Bootstrap.Form.Fieldset as Fieldset
import Bootstrap.Utilities.Spacing as Spacing
import Bootstrap.Utilities.Display as Display
import Bootstrap.Utilities.Border as Border
import Bootstrap.Utilities.Flex as Flex
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Text as Text

import Select as Autocomplete

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as JP

import List
import Url
import Http
import Api
import Debug
import Maybe

import ContextMapping.CollaborationId as ContextMapping exposing(CollaborationId)
import ContextMapping.Collaborator as Collaborator exposing(Collaborator)
import ContextMapping.RelationshipType as RelationshipType exposing(..)
import ContextMapping.Collaboration as ContextMapping exposing (..)
import BoundedContext.BoundedContextId as BoundedContext exposing(BoundedContextId)
import BoundedContext as BoundedContext
import Domain
import Domain.DomainId as Domain
import String


type alias DomainDependency =
  { id : Domain.DomainId
  , name : String }


type alias BoundedContextDependency =
  { id : BoundedContextId
  , name: String
  , domain: DomainDependency }


type CollaboratorReference
  = BoundedContext BoundedContextDependency
  | Domain DomainDependency
  | ExternalSystem String
  | Frontend String


type CollaboratorReferenceType
  = BoundedContextType (Maybe BoundedContextDependency) Autocomplete.State
  | DomainType (Maybe DomainDependency) Autocomplete.State
  | ExternalSystemType (Maybe String)
  | FrontendType (Maybe String)


type RelationshipEdit
  = SymmetricCollaboration (Maybe SymmetricRelationship)
  | CustomerSupplierCollaboration (Maybe InitiatorCustomerSupplierRole)
  | UpstreamCollaboration (Maybe UpstreamRelationship) (Maybe DownstreamRelationship)
  | DownstreamCollaboration (Maybe DownstreamRelationship) (Maybe UpstreamRelationship)
  | UnknownCollaboration


type alias DefineRelationshipType =
  { collaboration : Collaboration
  , modalVisibility : Modal.Visibility
  , relationshipEdit : Maybe RelationshipEdit
  , relationship : Maybe RelationshipType
  }


type alias AddCollaboration =
  { selectedCollaborator : Maybe CollaboratorReferenceType
  , dependencySelectState : Autocomplete.State
  , description : String
  , collaborator : Maybe Collaborator
  }


type alias Model =
  { boundedContextId : BoundedContextId
  , config : Api.Configuration
  , newCollaborations : Maybe AddCollaboration
  , defineRelationship : Maybe DefineRelationshipType
  , availableDependencies : List CollaboratorReference
  , inboundCollaboration : List ContextMapping.Collaboration
  , outboundCollaboration : List ContextMapping.Collaboration
  }


initAddCollaboration : AddCollaboration
initAddCollaboration =
  { selectedCollaborator = Nothing
  , dependencySelectState = Autocomplete.newState "collaboration-select"
  , description = ""
  , collaborator = Nothing
  }


initRelationshipEdit : RelationshipType -> RelationshipEdit
initRelationshipEdit relationshipType =
  case relationshipType of
    Symmetric s ->
      s |> Just |> SymmetricCollaboration
    (UpstreamDownstream (CustomerSupplierRelationship role)) ->
      role |> Just |> CustomerSupplierCollaboration
    (UpstreamDownstream (UpstreamDownstreamRelationship UpstreamRole upstream downstream)) ->
      UpstreamCollaboration (Just upstream) (Just downstream)
    (UpstreamDownstream (UpstreamDownstreamRelationship DownstreamRole upstream downstream)) ->
      DownstreamCollaboration (Just downstream) (Just upstream)
    Unknown ->
      UnknownCollaboration


initDefineRelationshipType : Collaboration -> DefineRelationshipType
initDefineRelationshipType collaboration =
  { collaboration = collaboration
  , modalVisibility = Modal.shown
  , relationshipEdit = collaboration |> ContextMapping.relationship |> Maybe.map initRelationshipEdit
  , relationship = Nothing
  }
  |> updateRelationshipEdit


init : Api.Configuration -> BoundedContext.BoundedContext ->  (Model, Cmd Msg)
init config context =
  (
    { config = config
    , boundedContextId = context |> BoundedContext.id
    , availableDependencies = []
    , inboundCollaboration = []
    , outboundCollaboration = []
    , newCollaborations = Nothing
    , defineRelationship = Nothing
    }
  , Cmd.batch
    [ loadBoundedContexts config
    , loadDomains config
    , loadConnections config (context |> BoundedContext.id)
    ]
  )

-- UPDATE

type CollaboratorReferenceMsg
  = SelectCollaborationType CollaboratorReferenceType
  | SelectBoundedContextMsg (Autocomplete.Msg BoundedContextDependency)
  | OnBoundedContextSelect (Maybe BoundedContextDependency)
  | SelectDomainMsg (Autocomplete.Msg DomainDependency)
  | OnDomainSelect (Maybe DomainDependency)
  | ExternalSystemCaption String
  | FrontendCaption String

type AddCollaborationMsg
  = CollaboratorSelection CollaboratorReferenceMsg
  | SetDescription String

type Msg
  = AddCollaborationMsg AddCollaborationMsg
  | BoundedContextsLoaded (Result Http.Error (List BoundedContextDependency))
  | DomainsLoaded (Result Http.Error (List DomainDependency))
  | ConnectionsLoaded (Result Http.Error (List CollaborationType))

  | StartAddingConnection
  | AddInboundConnection Collaborator String
  | AddOutboundConnection Collaborator String
  | InboundConnectionAdded (Api.ApiResponse Collaboration)
  | OutboundConnectionAdded (Api.ApiResponse Collaboration)
  | CancelAddingConnection

  | StartToDefineRelationship Collaboration
  | SetRelationship (Maybe RelationshipEdit)
  | DefineRelationship CollaborationId RelationshipType
  | RelationshipTypeDefined (Api.ApiResponse Collaboration)
  | CancelRelationshipDefinition

  | RemoveInboundConnection Collaboration
  | RemoveOutboundConnection Collaboration
  | InboundConnectionRemoved (Api.ApiResponse CollaborationId)
  | OutboundConnectionRemoved (Api.ApiResponse CollaborationId)

updateCollaboratorSelection : CollaboratorReferenceMsg -> Maybe CollaboratorReferenceType -> (Maybe CollaboratorReferenceType, Cmd CollaboratorReferenceMsg)
updateCollaboratorSelection msg model =
  case (msg, model) of
    (SelectCollaborationType t, _) ->
      (Just t, Cmd.none)
    (SelectBoundedContextMsg selMsg, Just (BoundedContextType sel state)) ->
      let
        ( updated, cmd ) =
          Autocomplete.update selectBoundedContextConfig selMsg state
      in
        ( Just <| BoundedContextType sel updated, cmd )
    (OnBoundedContextSelect context, Just (BoundedContextType _ state)) ->
      ( Just <| BoundedContextType context state, Cmd.none)
    (SelectDomainMsg selMsg, Just (DomainType sel state)) ->
      let
        ( updated, cmd ) =
          Autocomplete.update selectDomainConfig selMsg state
      in
        ( Just <| DomainType sel updated, cmd )
    (OnDomainSelect domain, Just (DomainType _ state)) ->
      ( Just <| DomainType domain state, Cmd.none)
    (ExternalSystemCaption caption, Just (ExternalSystemType _)) ->
      ( if caption |> String.isEmpty
        then Nothing
        else Just caption
        |> ExternalSystemType
        |> Just
      , Cmd.none
      )
    (FrontendCaption caption, Just (FrontendType _)) ->
      ( if caption |> String.isEmpty
        then Nothing
        else Just caption
        |> FrontendType
        |> Just
      , Cmd.none
      )
    _ ->
      (model, Cmd.none)


updateRelationshipEdit : DefineRelationshipType -> DefineRelationshipType
updateRelationshipEdit model =
 case model.relationshipEdit of
    Just relationshipType ->
      let
        relationship =
          case relationshipType of
            UnknownCollaboration ->
              Just RelationshipType.Unknown
            SymmetricCollaboration st ->
              Maybe.map RelationshipType.Symmetric st
            CustomerSupplierCollaboration (Just role) ->
              RelationshipType.CustomerSupplierRelationship role
              |> UpstreamDownstream
              |> Just
            UpstreamCollaboration upstreamRelation downstreamRelation ->
              Maybe.map3 RelationshipType.UpstreamDownstreamRelationship
                (Just RelationshipType.UpstreamRole)
                upstreamRelation
                downstreamRelation
              |> Maybe.map UpstreamDownstream
            DownstreamCollaboration downstreamRelation upstreamRelation ->
              Maybe.map3 RelationshipType.UpstreamDownstreamRelationship
                (Just RelationshipType.DownstreamRole)
                upstreamRelation
                downstreamRelation
              |> Maybe.map UpstreamDownstream
            _ ->
              Nothing
      in
        { model | relationship = relationship }
    _ ->
      { model | relationship = Nothing }


updateCollaborationDefinition : AddCollaboration ->  AddCollaboration
updateCollaborationDefinition model =
  let
    getCollaborator collaboratorType =
      case collaboratorType of
        BoundedContextType (Just bc) _ ->
          Just <| Collaborator.BoundedContext bc.id
        DomainType (Just d) _ ->
          Just <| Collaborator.Domain d.id
        ExternalSystemType (Just e) ->
          Just <| Collaborator.ExternalSystem e
        FrontendType (Just f) ->
          Just <| Collaborator.Frontend f
        _ ->
          Nothing
  in case model.selectedCollaborator of
    Just collaboratorType ->
        { model | collaborator = getCollaborator collaboratorType }
    _ ->
      { model | collaborator = Nothing }


updateCollaboration : AddCollaborationMsg -> AddCollaboration -> (AddCollaboration, Cmd AddCollaborationMsg)
updateCollaboration msg model =
  case msg of
    CollaboratorSelection bcMsg ->
      let
        (updated, cmd) =
          updateCollaboratorSelection bcMsg model.selectedCollaborator
        in
          ( updateCollaborationDefinition { model | selectedCollaborator = updated}
          , cmd |> Cmd.map CollaboratorSelection
          )
    SetDescription d ->
      ( { model | description = d}, Cmd.none)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    BoundedContextsLoaded (Ok contexts) ->
      ( { model | availableDependencies = List.append model.availableDependencies (contexts |> List.map BoundedContext) }
      , Cmd.none
      )
    DomainsLoaded (Ok domains) ->
      ( { model | availableDependencies = List.append model.availableDependencies (domains |> List.map Domain) }
      , Cmd.none
      )
    ConnectionsLoaded (Ok connections) ->
      let
        (inbound, outbound) =
          connections
          |> List.foldl(\c (inbounds,outbounds) ->
              case c of
                Inbound inboundColl ->
                  (inboundColl :: inbounds,outbounds)
                Outbound outboundColl ->
                  (inbounds,outboundColl :: outbounds)
            ) ([],[])

      in
        ( { model
          | inboundCollaboration = List.append model.inboundCollaboration inbound
          , outboundCollaboration = List.append model.outboundCollaboration outbound
          }
        , Cmd.none
        )

    StartAddingConnection ->
      ( { model | newCollaborations = Just initAddCollaboration }, Cmd.none)
    AddCollaborationMsg col ->
      case model.newCollaborations of
        Just adding ->
          let
            (m, cmd) = updateCollaboration col adding
          in
            ( {model | newCollaborations = Just m }, cmd |> Cmd.map AddCollaborationMsg)
        _ ->
          (model, Cmd.none)

    AddInboundConnection coll desc ->
      ( model, ContextMapping.defineInboundCollaboration model.config model.boundedContextId coll desc InboundConnectionAdded )
    AddOutboundConnection coll desc ->
      ( model, ContextMapping.defineOutboundCollaboration model.config model.boundedContextId coll desc OutboundConnectionAdded )

    InboundConnectionAdded (Ok result) ->
      ( { model
        | inboundCollaboration = result :: model.inboundCollaboration
        , newCollaborations = Nothing
        }
      , Cmd.none
      )
    OutboundConnectionAdded (Ok result) ->
      ( { model
        | outboundCollaboration = result :: model.outboundCollaboration
        , newCollaborations = Nothing
        }
      , Cmd.none
      )

    CancelAddingConnection ->
      ( {model | newCollaborations = Nothing }, Cmd.none)

    RemoveInboundConnection coll ->
      ( model, ContextMapping.endCollaboration model.config (ContextMapping.id coll) InboundConnectionRemoved )
    RemoveOutboundConnection coll ->
      ( model, ContextMapping.endCollaboration model.config (ContextMapping.id coll) OutboundConnectionRemoved )

    InboundConnectionRemoved (Ok result) ->
      ( { model | inboundCollaboration =
          model.inboundCollaboration
          |> List.filter (\i -> (i |> ContextMapping.id) /= result)
        }
      , Cmd.none
      )
    OutboundConnectionRemoved (Ok result) ->
      ( { model | outboundCollaboration =
          model.outboundCollaboration
          |> List.filter (\i -> (i |> ContextMapping.id) /= result)
        }
      , Cmd.none
      )

    StartToDefineRelationship collaboration ->
      ( { model | defineRelationship = collaboration |> initDefineRelationshipType |> Just }
      , Cmd.none
      )

    SetRelationship relationship ->
      case model.defineRelationship of
        Just defining ->
          ( { model
            | defineRelationship =
                { defining | relationshipEdit = relationship} |> updateRelationshipEdit |> Just
            }
          , Cmd.none
          )
        Nothing ->
          (model, Cmd.none)

    DefineRelationship collaborationId relationship ->
      (model, ContextMapping.defineRelationshipType model.config collaborationId relationship RelationshipTypeDefined)

    RelationshipTypeDefined (Ok collaboration) ->
      let
        updateCollaborationType c =
          if (c |> ContextMapping.id) == (collaboration |> ContextMapping.id)
          then collaboration
          else c
      in
        ( { model
          | defineRelationship = Nothing
          , inboundCollaboration = model.inboundCollaboration |> List.map updateCollaborationType
          , outboundCollaboration = model.outboundCollaboration |> List.map updateCollaborationType
          }
        , Cmd.none
        )

    CancelRelationshipDefinition ->
      ( { model | defineRelationship = Nothing }
      , Cmd.none
      )

    _ ->
      let
        _ = Debug.log "Dependencies msg" msg
        _ = Debug.log "Dependencies model" model
      in
        (model, Cmd.none)

-- VIEW


filterLowerCase : Int -> (item -> List String) -> String -> List item -> Maybe (List item)
filterLowerCase minChars stringsToCompare query items =
  if String.length query < minChars then
      Nothing
  else
    let
      lowerQuery = query |> String.toLower
      containsLowerString text =
        text
        |> String.toLower
        |> String.contains lowerQuery
      searchable i =
        i
        |> stringsToCompare
        |> List.any containsLowerString
      in
        items
        |> List.filter searchable
        |> Just


selectBoundedContextConfig : Autocomplete.Config CollaboratorReferenceMsg BoundedContextDependency
selectBoundedContextConfig =
    Autocomplete.newConfig
        { onSelect = OnBoundedContextSelect
        , toLabel = (\bc -> bc.domain.name ++ " - " ++ bc.name)
        , filter = filterLowerCase 2 (\bc -> [ bc.name, bc.domain.name ])
        }
        |> Autocomplete.withCutoff 12
        |> Autocomplete.withInputClass "text-control border rounded form-control-lg"
        |> Autocomplete.withInputWrapperClass ""
        |> Autocomplete.withItemClass " border p-2 "
        |> Autocomplete.withMenuClass "bg-light"
        |> Autocomplete.withNotFound "No matches"
        |> Autocomplete.withNotFoundClass "text-danger"
        |> Autocomplete.withHighlightedItemClass "bg-white"
        |> Autocomplete.withPrompt "Search for a Bounded Context"
        |> Autocomplete.withItemHtml (\bc ->
            Html.span []
              [ Html.h6 [ class "text-muted" ] [ text bc.domain.name ]
              , Html.span [] [ text bc.name ]
              ]
        )


selectDomainConfig : Autocomplete.Config CollaboratorReferenceMsg DomainDependency
selectDomainConfig =
    Autocomplete.newConfig
        { onSelect = OnDomainSelect
        , toLabel = (\domain -> domain.name )
        , filter = filterLowerCase 2 (\domain -> [ domain.name ])
        }
        |> Autocomplete.withCutoff 12
        |> Autocomplete.withInputClass "text-control border rounded form-control-lg"
        |> Autocomplete.withInputWrapperClass ""
        |> Autocomplete.withItemClass " border p-2 "
        |> Autocomplete.withMenuClass "bg-light"
        |> Autocomplete.withNotFound "No matches"
        |> Autocomplete.withNotFoundClass "text-danger"
        |> Autocomplete.withHighlightedItemClass "bg-white"
        |> Autocomplete.withPrompt "Search for a Domain"
        |> Autocomplete.withItemHtml (\domain ->
          Html.span [] [ text domain.name ]
        )


onSubmitMaybe : Maybe msg -> Html.Attribute msg
onSubmitMaybe maybeMsg =
  -- https://thoughtbot.com/blog/advanced-dom-event-handlers-in-elm
  let
    preventDefault m =
      ( m, True )
  in case maybeMsg of
    Just msg ->
      Html.Events.preventDefaultOn "submit" (Decode.map preventDefault (Decode.succeed msg))
    Nothing ->
      Html.Events.preventDefaultOn "submit" (Decode.map preventDefault (Decode.fail "No message to submit"))


translateSymmetricRelationship relationship =
  case relationship of
    SharedKernel -> ("Shared Kernel", "SK")
    Partnership -> ("Partnership","PS")
    SeparateWays -> ("Separate Ways","SW")
    BigBallOfMud -> ("Big Ball of Mud","BBoM")


translateUpstreamRelationship relationship =
  case relationship of
    Upstream -> ("Upstream","US")
    PublishedLanguage -> ("Published Language","PL")
    OpenHost -> ("Open Host Service","OHS")

translateDownstreamRelationship relationship =
  case relationship of
    Downstream -> ("Downstream","DS")
    AntiCorruptionLayer -> ("Anti Corruption Layer","ACL")
    Conformist -> ("Conformist","CF")

concatTuple operation (x1,y1) (x2,y2) =
  ( operation x1 x2
  , operation y1 y2
  )


translateUpstreamDownstreamRelationship relationship =
  case relationship of
    CustomerSupplierRelationship role ->
      case role of
        CustomerRole ->
          (("Customer","Supplier"),("CUS","SUP"))
        SupplierRole ->
          (("Supplier","Customer"), ("SUP","CUS"))
    UpstreamDownstreamRelationship role ut dt ->
      concatTuple
        (\upstream downstream ->
          case role of
            UpstreamRole ->
              (upstream,downstream)
            DownstreamRole ->
              (downstream,upstream)
        )
        (translateUpstreamRelationship ut)
        ( translateDownstreamRelationship dt )

type alias LabelAndDescription = (String, String)

type alias ResolveCollaboratorCaption = Collaborator -> LabelAndDescription
type alias ResolveCollaboratorCaptionFromCollaboration = Collaboration -> LabelAndDescription

collaboratorCaptionFromCollaboration : List CollaboratorReference -> (Collaboration -> Collaborator) -> Collaboration -> LabelAndDescription
collaboratorCaptionFromCollaboration items collaboratorSelection collaboration =
  collaboratorCaption items (collaboratorSelection collaboration)

collaboratorCaption : List CollaboratorReference -> Collaborator -> LabelAndDescription
collaboratorCaption items collaborator=
  case collaborator of
    Collaborator.BoundedContext bc ->
      items
      |> List.filterMap (\r ->
        case r of
          BoundedContext bcr ->
            if bcr.id == bc then
              Just <|
                ( bcr.name
                , "[in Domain '" ++ bcr.domain.name  ++ "']"
                )
            else
              Nothing
          _ ->
            Nothing
      )
      |> List.head
      |> Maybe.withDefault ("Unknown Bounded Context", "")
    Collaborator.Domain d ->
      items
      |> List.filterMap (\r ->
        case r of
          Domain dr ->
            if dr.id == d
            then Just (dr.name, "[Domain]")
            else Nothing
          _ ->
            Nothing
      )
      |> List.head
      |> Maybe.withDefault ("Unknown Domain", "")
    Collaborator.ExternalSystem s ->
      ( s
      , "[External System]"
      )
    Collaborator.Frontend s ->
      ( s
      , "[Frontend]"
      )
    Collaborator.UserInteraction s ->
      ( s
      , "[User Interaction]"
      )


captionAndDescription caption description =
  Html.span []
    [ text <| caption
    , Form.help [] [ text description ]
    ]

captionAndInlineDescriptionView (caption, description) =
  Html.span []
    [ text <| caption
    , Form.helpInline [ Spacing.ml1 ] [ text description ]
    ]

labelAbbreviationAndDescription caption abbreviation description =
    Radio.label [] [ captionAndDescription (caption ++ " (" ++ abbreviation ++ ")") description ]

specifyRelationshipType relationshipType =
  let
    symmetricConfiguration =
      let
        renderOption idValue descriptionText value =
          let
            (label, abbreviation) = translateSymmetricRelationship value
          in Radio.createAdvanced
            [ Radio.id idValue
            , Radio.onClick (SetRelationship (Just <| SymmetricCollaboration <| Just value))
            , Radio.checked (
                case relationshipType of
                  Just (SymmetricCollaboration (Just x)) ->
                    x == value
                  _ ->
                    False
                )
            ]
            ( labelAbbreviationAndDescription label abbreviation descriptionText )
        options =
          Radio.label []
            ( ( captionAndDescription "Symmetric" "The relationship between the collaborators is equal or symmetric." )
              :: [ Html.div []
                (  Radio.radioList "symmetricOptions"
                  [ renderOption "sharedKernelOption" "Technical artefacts are shared between the collaborators" SharedKernel
                  , renderOption "PartnershipOption" "The collaborators work together to reach a common goal" Partnership
                  , renderOption "separateWaysOption" "The collaborators decided to NOT use information, but rather work in seperate ways" SeparateWays
                  , renderOption "bigBallOfMudOption" "It's complicated..."  BigBallOfMud
                  ]
                )
              ]
          )
      in
        Radio.createAdvanced
          [ Radio.id "symmetricType"
          , Radio.onClick (SetRelationship (Just <| SymmetricCollaboration Nothing))
          , Radio.checked (
              case relationshipType of
                Just (SymmetricCollaboration _) ->
                  True
                _ ->
                  False
              )
          ]
          options

    customerSupplierConfiguration =
      Radio.createAdvanced
        [ Radio.id "customerType"
        , Radio.onClick (SetRelationship (Just <| CustomerSupplierCollaboration Nothing))
        , Radio.checked (
            case relationshipType of
              Just (CustomerSupplierCollaboration _) ->
                True
              _ ->
                False
          )
        ]
        ( Radio.label [Spacing.pt1]
          [ captionAndDescription "Customer/Supplier" "There is a cooperation with the collaborator that can be described as a customer/supplier relationship."
          , Html.div [ ]
            ( Radio.radioList "customerSupplierOptions"
              [ Radio.createAdvanced
                [ Radio.id "isCustomerOption"
                , Radio.checked (relationshipType == (Just <| CustomerSupplierCollaboration <| Just CustomerRole))
                , Radio.onClick (SetRelationship (Just <| CustomerSupplierCollaboration <| Just CustomerRole))
                , Radio.inline
                ]
                ( labelAbbreviationAndDescription "Customer" "CUS" "The collaborator is in the customer role" )
              , Radio.createAdvanced
                [ Radio.id "isSupplierOption"
                , Radio.checked (relationshipType == (Just <| CustomerSupplierCollaboration <| Just SupplierRole))
                , Radio.onClick (SetRelationship (Just <| CustomerSupplierCollaboration <| Just SupplierRole))
                , Radio.inline
                ]
                ( labelAbbreviationAndDescription "Supplier" "SUP" "The collaborator is in the supplier role" )
              ]
            )
          ]
        )

    upstreamConfiguration =
      let
        isUpstream upstreamConfig =
          case relationshipType of
            (Just (UpstreamCollaboration (Just up) _)) ->
              up == upstreamConfig
            _ ->
              False
        setUpstream upstreamConfig =
          case relationshipType of
            (Just (UpstreamCollaboration _ down)) ->
              SetRelationship (Just <| UpstreamCollaboration (Just upstreamConfig) down)
            _ ->
              SetRelationship (Just <| UpstreamCollaboration (Just upstreamConfig) Nothing)

        isDownstream downstreamConfig =
          case relationshipType of
            (Just (UpstreamCollaboration _ (Just down))) ->
              down == downstreamConfig
            _ ->
              False
        setDownstream downstreamConfig =
          case relationshipType of
            (Just (UpstreamCollaboration up _)) ->
              SetRelationship (Just <| UpstreamCollaboration up (Just downstreamConfig))
            _ ->
              SetRelationship (Just <| UpstreamCollaboration Nothing (Just downstreamConfig))

        options =
          Radio.label []
            [ captionAndDescription "Upstream" "The collaborator is upstream and I depend on changes."
            , Html.div [ class "row" ]
              [ Form.group [ Form.attrs [ class "col"]  ]
                ( Html.span[] [ text "Describe the collaborator:" ]
                :: Radio.radioList "upstream-upstreamOptions"
                  [ Radio.createAdvanced
                    [ Radio.id "upstream-upstreamOption"
                    , Radio.checked (isUpstream Upstream)
                    , Radio.onClick (setUpstream Upstream)
                    ]
                    ( labelAbbreviationAndDescription "Upstream" "US" "The collaborator is just Upstream" )
                  , Radio.createAdvanced
                    [ Radio.id "upstream-publishedLanguageOption"
                    , Radio.checked (isUpstream PublishedLanguage)
                    , Radio.onClick (setUpstream PublishedLanguage)
                    ]
                    ( labelAbbreviationAndDescription "Published Language" "PL" "The collaborator is using a Published Language" )
                  , Radio.createAdvanced
                    [ Radio.id "upstream-openHostOption"
                    , Radio.checked (isUpstream OpenHost)
                    , Radio.onClick (setUpstream OpenHost)
                    ]
                    ( labelAbbreviationAndDescription "Open Host Service" "OHS" "The collaborator is providing an Open Host Service" )
                  ]
                )
              , Form.group [ Form.attrs [ class "col"]  ]
                ( Html.span[] [ text "Describe your relationship with the collaborator:" ]
                :: Radio.radioList "upstream-downstreamOptions"
                  [ Radio.createAdvanced
                    [ Radio.id "upstream-downstreamOption"
                    , Radio.checked (isDownstream Downstream)
                    , Radio.onClick (setDownstream Downstream)
                    ]
                    ( labelAbbreviationAndDescription "Downstream" "DS" "I'm just Downstream" )
                  , Radio.createAdvanced
                    [ Radio.id "upstream-aclOption"
                    , Radio.checked (isDownstream AntiCorruptionLayer)
                    , Radio.onClick (setDownstream AntiCorruptionLayer)
                    ]
                    ( labelAbbreviationAndDescription "Anti-Corruption-Layer" "ACL" "I'm using an Anti-Corruption-Layer to shield me from changes" )
                  , Radio.createAdvanced
                    [ Radio.id "upstream-cfOption"
                    , Radio.checked (isDownstream Conformist)
                    , Radio.onClick (setDownstream Conformist)
                    ]
                    ( labelAbbreviationAndDescription "Conformist" "CF" "I'm Conformist to upstream changes" )
                  ]
                )
              ]
            ]
        in
        Radio.createAdvanced
          [ Radio.id "upstream-upstreamType"
          , Radio.onClick (SetRelationship (Just <| UpstreamCollaboration Nothing Nothing))
          , Radio.checked (
              case relationshipType of
                Just (UpstreamCollaboration _ _) ->
                  True
                _ ->
                  False
            )
          ]
          options

    downstreamConfiguration =
      let
        isUpstream upstreamConfig =
          case relationshipType of
            (Just (DownstreamCollaboration _ (Just up))) ->
              up == upstreamConfig
            _ ->
              False
        setUpstream upstreamConfig =
          case relationshipType of
            (Just (DownstreamCollaboration down _ )) ->
              SetRelationship (Just <| DownstreamCollaboration down (Just upstreamConfig))
            _ ->
              SetRelationship (Just <| DownstreamCollaboration Nothing (Just upstreamConfig) )

        isDownstream downstreamConfig =
          case relationshipType of
            (Just (DownstreamCollaboration (Just down) _ )) ->
              down == downstreamConfig
            _ ->
              False
        setDownstream downstreamConfig =
          case relationshipType of
            (Just (DownstreamCollaboration _ up)) ->
              SetRelationship (Just <| DownstreamCollaboration (Just downstreamConfig) up)
            _ ->
              SetRelationship (Just <| DownstreamCollaboration (Just downstreamConfig) Nothing)

        options =
          Radio.label []
            [ captionAndDescription "Downstream" "The collaborator is downstream and they depend on my changes."
            , Html.div [ class "row" ]
              [ Form.group [ Form.attrs [ class "col"] ]
                ( Html.span[] [ text "Describe the collaborator:" ]
                :: Radio.radioList "downstream-downstreamOptions"
                  [ Radio.createAdvanced
                    [ Radio.id "downstream-downstreamOption"
                    , Radio.checked (isDownstream Downstream)
                    , Radio.onClick (setDownstream Downstream)
                    ]
                    ( labelAbbreviationAndDescription "Downstream" "DS" "The collaborator is just Downstream" )
                  , Radio.createAdvanced
                    [ Radio.id "downstream-aclOption"
                    , Radio.checked (isDownstream AntiCorruptionLayer)
                    , Radio.onClick (setDownstream AntiCorruptionLayer)
                    ]
                    ( labelAbbreviationAndDescription "Anti-Corruption-Layer" "ACL" "The collaborator is using an Anti-Corruption-Layer to shield from my changes" )
                  , Radio.createAdvanced
                    [ Radio.id "downstream-cfOption"
                    , Radio.checked (isDownstream Conformist)
                    , Radio.onClick (setDownstream Conformist)
                    ]
                    ( labelAbbreviationAndDescription "Conformist" "CF" "The collaborator is Conformist to my upstream changes" )
                  ]
                )
              , Form.group [ Form.attrs [ class "col"] ]
                ( Html.span[] [ text "Describe your relationship with the collaborator:" ]
                :: Radio.radioList "downstream-upstreamOptions"
                  [ Radio.createAdvanced
                    [ Radio.id "downstream-upstreamOption"
                    , Radio.checked (isUpstream Upstream)
                    , Radio.onClick (setUpstream Upstream)
                    ]
                    ( labelAbbreviationAndDescription "Upstream" "US" "I'm just Upstream" )
                  , Radio.createAdvanced
                    [ Radio.id "downstream-publishedLanguageOption"
                    , Radio.checked (isUpstream PublishedLanguage)
                    , Radio.onClick (setUpstream PublishedLanguage)
                    ]
                    ( labelAbbreviationAndDescription "Published Language" "PL" "I'm using a Published Language" )
                  , Radio.createAdvanced
                    [ Radio.id "downstream-openHostOption"
                    , Radio.checked (isUpstream OpenHost)
                    , Radio.onClick (setUpstream OpenHost)
                    ]
                    ( labelAbbreviationAndDescription "Open Host Service" "OHS" "I'm providing an Open Host Service" )
                  ]
                )

              ]
            ]
        in
        Radio.createAdvanced
          [ Radio.id "downstream-upstreamType"
          , Radio.onClick (SetRelationship (Just <| DownstreamCollaboration Nothing Nothing))
          , Radio.checked (
              case relationshipType of
                Just (DownstreamCollaboration _ _) ->
                  True
                _ ->
                  False
            )
          ]
          options

    unknownConfiguration =
      Radio.createAdvanced
        [ Radio.id "uknownType"
        , Radio.onClick (SetRelationship (Just UnknownCollaboration))
        , Radio.checked (relationshipType == Just UnknownCollaboration)
        ]
        ( labelAbbreviationAndDescription  "Unkown" "?" "The exact description of the relationship unknown or you are not sure how to describe it."
        )

  in
    Radio.radioList "collaborationTypeSelection"
      [ unknownConfiguration
      , symmetricConfiguration
      , customerSupplierConfiguration
      , upstreamConfiguration
      , downstreamConfiguration
      ]

buildFields  : List CollaboratorReference -> AddCollaboration -> List (Html AddCollaborationMsg)
buildFields dependencies model =
  let

    -- selectedItem =
    --   case model.selectedCollaborator of
    --     Just (Just (BoundedContextType s)) -> [ s ]
    --     Nothing -> []

    -- TODO: this is probably very unefficient
    -- existingDependencies =
    --   model.existingCollaboration
    --   |> List.map Tuple.first

    -- relevantDependencies =
    --   dependencies
    --   |> List.filter (\d -> existingDependencies |> List.any (\existing -> (d |> toCollaborator)  == existing ) |> not )

    radioList =
      Radio.radioList "collaboratorSelection"
        [ Radio.create
          [ Radio.id "boundedContextOption"
          , Radio.onClick (SelectCollaborationType (BoundedContextType Nothing (Autocomplete.newState "boundedContext")))
          , Radio.checked (
              case model.selectedCollaborator of
                Just (BoundedContextType _ _) -> True
                _ -> False
            )
          ]
          "Bounded Context"
        , Radio.create
          [ Radio.id "domainOption"
          , Radio.onClick (SelectCollaborationType (DomainType Nothing (Autocomplete.newState "domain")))
          , Radio.checked (
              case model.selectedCollaborator of
                Just (DomainType _ _) -> True
                _ -> False
            )
          ]
          "Domain"
        , Radio.create
          [ Radio.id "externalSystemOption"
          , Radio.onClick (SelectCollaborationType (ExternalSystemType Nothing))
          , Radio.checked (
              case model.selectedCollaborator of
                Just (ExternalSystemType _) -> True
                _ -> False
            )
          ]
          "External System"
         , Radio.create
          [ Radio.id "frontendOption"
          , Radio.onClick (SelectCollaborationType (FrontendType Nothing))
          , Radio.checked (
              case model.selectedCollaborator of
                Just (FrontendType _) -> True
                _ -> False
            )
          ]
          "Frontend"
        ]

    asList maybe =
      case maybe of
        Just value -> [ value ]
        Nothing -> []

    collaboratorInputbox =
      case model.selectedCollaborator of
        Just selectedType ->
          case selectedType of
            BoundedContextType selected state ->
                Autocomplete.view
                selectBoundedContextConfig
                state
                ( dependencies
                  |> List.filterMap (\item ->
                      case item of
                        BoundedContext bc ->
                          Just bc
                        _ ->
                          Nothing
                    )
                )
                (asList selected)
              |> Html.map SelectBoundedContextMsg
            DomainType selected state ->
              Autocomplete.view
                selectDomainConfig
                state
                ( dependencies
                  |> List.filterMap (\item ->
                      case item of
                        Domain bc ->
                          Just bc
                        _ ->
                          Nothing
                    )
                )
                (asList selected)
              |> Html.map SelectDomainMsg
            ExternalSystemType value ->
              Input.text
                [ Input.value (value |> Maybe.withDefault "")
                , Input.placeholder "External System name"
                , Input.onInput ExternalSystemCaption
                ]
            FrontendType value ->
              Input.text
                [ Input.value (value |> Maybe.withDefault "")
                , Input.placeholder "Frontend name"
                , Input.onInput FrontendCaption
                ]
        Nothing ->
          Input.text
            [ Input.disabled True
            , Input.placeholder "Select an option"]
  in
    [ Form.group []
      [ Form.label [ for "collaboratorSelection"] [ text "Select the collaborator of the connection" ]
      , Html.div [] radioList
      , collaboratorInputbox
      ]
      |> Html.map CollaboratorSelection
    , Form.group []
      [ Form.label [ for "description" ] [ text "An optional description of the collaboration" ]
      , Textarea.textarea
          [ Textarea.id "description"
          , Textarea.rows 3
          , Textarea.value model.description
          , Textarea.onInput SetDescription
          ]
      ]
    ]


viewAddConnection : List CollaboratorReference -> Maybe AddCollaboration -> Html Msg
viewAddConnection dependencies adding =
  case adding of
    Just model ->
      Html.form []
      [ Card.config [ Card.attrs [ class "mb-3", class "shadow" ] ]
        |> Card.headerH4 [] [ text "Add a new collaborator"]
        |> Card.block []
          ( buildFields dependencies model
            |> List.map (Html.map AddCollaborationMsg)
            |> List.map Block.custom
          )
        |> Card.footer []
          [ ButtonGroup.toolbar [Flex.justifyBetween]
            [ ButtonGroup.buttonGroupItem []
              [ ButtonGroup.button
                [ Button.primary
                , Button.disabled (model.collaborator == Nothing)
                , model.collaborator
                  |> Maybe.map (\c -> AddInboundConnection c model.description)
                  |> Maybe.map Button.onClick
                  |> Maybe.withDefault (Button.attrs [])
                ]
                [ text "Add as inbound connection" ]
              , ButtonGroup.button
                [ Button.primary
                , Button.disabled (model.collaborator == Nothing)
                , model.collaborator
                  |> Maybe.map (\c -> AddOutboundConnection c model.description)
                  |> Maybe.map Button.onClick
                  |> Maybe.withDefault (Button.attrs [])
                ]
                [ text "Add as outbound connection" ]
              ]
            , ButtonGroup.buttonGroupItem [ ButtonGroup.attrs [ Spacing.ml1] ]
              [ ButtonGroup.button
                [ Button.secondary
                , Button.onClick (CancelAddingConnection)
                ]
                [ text "Cancel" ]
              ]
            ]
          ]
        |> Card.view
      ]
    Nothing ->
      Card.config [ Card.attrs [ class "mb-3", class "shadow" ], Card.align Text.alignXsCenter ]
      |> Card.block []
        [ Block.custom
          <| Button.button [ Button.primary, Button.onClick StartAddingConnection ] [ text "Add new Collaborator" ]
        ]
      |> Card.view


viewConnection : ResolveCollaboratorCaption -> Bool -> List Collaboration -> Html Msg
viewConnection resolveCaption isInbound collaborations =
  let
    resolveCollaborator =
      if isInbound
      then ContextMapping.initiator
      else ContextMapping.recipient
    inboundCollaborator collaboration config =
      let
        description = ContextMapping.description collaboration
        relationship =
          case collaboration |> ContextMapping.relationship of
            Just r ->
              div [ Flex.block, Flex.justifyBetween ]
                [ case r of
                    Symmetric s ->
                      captionAndDescription
                        (s |> translateSymmetricRelationship |> Tuple.first)
                        "Symmetric"
                    UpstreamDownstream upstreamDownstreamType ->
                      captionAndDescription
                        ( upstreamDownstreamType
                         |> translateUpstreamDownstreamRelationship
                         |> Tuple.first
                         |> ( \(inboundType, outboundType) ->
                            if isInbound
                            then (inboundType ++ "/" ++ outboundType)
                            else (outboundType ++ "/" ++ inboundType)
                          )
                        )
                        "Upstream/Downstream"
                    Unknown ->
                      text "Unknown"
                , Button.button
                  [ Button.outlineSecondary
                  , Button.small
                  , Button.onClick (StartToDefineRelationship collaboration)
                  ]
                  [ text "Redefine Relationship"]
                ]
            Nothing ->
              div [ Flex.block, Flex.justifyCenter]
                [ Button.button
                  [ Button.outlinePrimary
                  , Button.small
                  , Button.onClick (StartToDefineRelationship collaboration)
                  ]
                  [ text "Define Relationship"]
                ]
      in
        config
          |> Card.block [ Block.attrs [ Border.bottom ] ]
            [ Block.titleH6 [ Flex.block, Flex.justifyBetween ]
              [ collaboration
                |> resolveCollaborator
                |> resolveCaption
                |> captionAndInlineDescriptionView
              , Button.button
                [ Button.outlineSecondary
                , Button.small
                , Button.onClick (RemoveInboundConnection collaboration)
                ]
                [ text "x" ]
              ]
            , Block.text [ class "text-muted" ] [ text <| Maybe.withDefault "" description ]
            , Block.custom <| relationship
          ]
    cardConfig =
      Card.config[]
  in
    div []
      [  Html.h6
        [ class "text-center", Spacing.p2 ]
        [ Html.strong [] [ text (if isInbound then "Inbound Connection" else "Outbound Connection") ] ]
      , collaborations
        |> List.foldl inboundCollaborator cardConfig
        |> Card.view
      ]


viewDefineRelationship : ResolveCollaboratorCaptionFromCollaboration -> Maybe DefineRelationshipType -> Html Msg
viewDefineRelationship resolveCaption defineRelationship =
  case defineRelationship of
    Just model ->
      Modal.config CancelRelationshipDefinition
        |> Modal.large
        |> Modal.scrollableBody True
        |> Modal.hideOnBackdropClick True
        |> Modal.h3 [] [ text "Relationship between collaborators" ]
        |> Modal.body []
          [ text "How would you describe the relationship with the collaborator "
          , model.collaboration
            |> resolveCaption
            |> captionAndInlineDescriptionView
          , div [] (specifyRelationshipType model.relationshipEdit)
          ]
        |> Modal.footer []
            [ Button.button
              [ Button.primary
              , model.relationship
              |> Maybe.map (DefineRelationship (ContextMapping.id model.collaboration))
              |> Maybe.map Button.onClick
              |> Maybe.withDefault (Button.attrs [])
              , Button.disabled (model.relationship == Nothing)
              ]
              [ text "Define Relationship" ]
            , Button.button
                [ Button.outlinePrimary
                , Button.attrs [ onClick CancelRelationshipDefinition ]
                ]
                [ text "Close" ]
            ]
        |> Modal.view model.modalVisibility
    Nothing ->
      text ""

viewConnections getCollaboratorCaption model =
  Grid.row []
    [ Grid.col []
      [ viewConnection getCollaboratorCaption True model.inboundCollaboration ]
    , Grid.col []
      [ viewConnection getCollaboratorCaption False model.outboundCollaboration ]
    ]


view : Model -> Html Msg
view model =
  div []
    [ Html.span
      [ class "text-center"
      , Display.block
      , style "background-color" "lightGrey"
      , Spacing.p2
      ]
      [ text "Dependencies and Relationships" ]
    , Form.help [] [ text "To create loosely coupled systems it's essential to be wary of dependencies. In this section you should write the name of each dependency and a short explanation of why the dependency exists." ]
    , viewConnections (collaboratorCaption model.availableDependencies) model
    , Grid.simpleRow
      [ Grid.col []
          [ viewAddConnection model.availableDependencies model.newCollaborations]
      ]
    , viewDefineRelationship
        ( collaboratorCaptionFromCollaboration
          model.availableDependencies
          (model.boundedContextId |> Collaborator.BoundedContext |> ContextMapping.otherCollaborator)
        )
        model.defineRelationship
    ]

domainDecoder : Decoder DomainDependency
domainDecoder =
  Domain.domainDecoder
  |> Decode.map (\d -> { id = d |> Domain.id, name = d |> Domain.name})

boundedContextDecoder : Decoder BoundedContextDependency
boundedContextDecoder =
  -- TODO: can we reuse BoundedContext.modelDecoder?
  Decode.succeed BoundedContextDependency
    |> JP.custom BoundedContext.idFieldDecoder
    |> JP.custom BoundedContext.nameFieldDecoder
    |> JP.required "domain" domainDecoder

loadBoundedContexts: Api.Configuration -> Cmd Msg
loadBoundedContexts config =
  Http.get
    { url = Api.allBoundedContexts [ Api.Domain ] |> Api.url config |> Url.toString
    , expect = Http.expectJson BoundedContextsLoaded (Decode.list boundedContextDecoder)
    }

loadDomains: Api.Configuration -> Cmd Msg
loadDomains config =
  Http.get
    { url = Api.domains [] |> Api.url config |> Url.toString
    , expect = Http.expectJson DomainsLoaded (Decode.list domainDecoder)
    }

loadConnections : Api.Configuration -> BoundedContextId -> Cmd Msg
loadConnections config context =
  let
    filterConnections connections =
      connections
      |> List.filterMap (ContextMapping.isCollaborator (Collaborator.BoundedContext context))
  in Http.get
    { url = Api.collaborations |> Api.url config |> Url.toString
    , expect = Http.expectJson ConnectionsLoaded (Decode.map filterConnections (Decode.list ContextMapping.modelDecoder))
    }