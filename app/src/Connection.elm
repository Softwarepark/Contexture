module Connection exposing (
    Collaboration,Collaboration2, Collaborations, CollaborationType(..), 
    noCollaborations, defineInboundCollaboration, defineOutboundCollaboration, defineRelationshipType,
    endCollaboration,
    isCollaborator,
    relationship, description, initiator, recipient, id, otherCollaborator,
    modelDecoder)

import Json.Encode as Encode
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as JP

import Url
import Http

import Api exposing(ApiResult)

import ContextMapping.CollaborationId as ContextMapping exposing (CollaborationId)
import ContextMapping.Collaborator as Collaborator exposing (Collaborator)
import ContextMapping.RelationshipType as RelationshipType exposing (RelationshipType)
import Domain
import Domain.DomainId as Domain
import BoundedContext.BoundedContextId exposing (BoundedContextId)
import Api exposing (collaboration)


type Collaboration
  = Collaboration CollaborationInternal
type Collaboration2 
  -- = Collaboration CollaborationInternal
  = Collaboration2 CollaborationInternal2
  

type alias CollaborationInternal =
    { id : CollaborationId
    , relationship : RelationshipType
    , description : Maybe String
    , communicationInitiator : Collaborator
    }

type alias CollaborationInternal2 =
    { id : CollaborationId
    , description : Maybe String
    , initiator : Collaborator
    , recipient : Collaborator
    , relationship : Maybe RelationshipType
    }


type alias Collaborations = List Collaboration

type CollaborationType
  = Inbound Collaboration2
  | Outbound Collaboration2

-- type CollaborationDefinition
--   = SymmetricCollaboration RelationshipType.SymmetricRelationship
--   | UpstreamCollaboration RelationshipType.UpstreamRelationship RelationshipType.DownstreamRelationship
--   | CustomerSupplierCollaboration RelationshipType.InitiatorCustomerSupplierRole
--   | DownstreamCollaboration RelationshipType.DownstreamRelationship RelationshipType.UpstreamCollaborator
--   | UnknownCollaboration Collaborator


noCollaborations : Collaborations
noCollaborations = []

endCollaboration : Api.Configuration -> CollaborationId -> ApiResult CollaborationId msg
endCollaboration url collaborationId =
  let
    api =
      Api.collaboration collaborationId

    request toMsg =
      Http.request
      { method = "DELETE"
      , url = api |> Api.url url |> Url.toString
      , body = Http.emptyBody
      , expect = Http.expectJson toMsg (Decode.succeed collaborationId)
      , timeout = Nothing
      , tracker = Nothing
      , headers = []
      }
  in
    request


defineInboundCollaboration : Api.Configuration -> BoundedContextId -> Collaborator -> String -> ApiResult Collaboration2 msg
defineInboundCollaboration url context connectionInitiator descriptionText =
  let
    api =
      Api.collaborations

    connectionRecipient = Collaborator.BoundedContext context

    request toMsg =
      Http.post
      { url = api |> Api.url url |> Url.toString
      , body = Http.jsonBody <|
              modelEncoder2 
                connectionInitiator
                connectionRecipient
                (if String.isEmpty descriptionText then Nothing else Just descriptionText)
                Nothing
      , expect = Http.expectJson toMsg modelDecoder
      }
    in
      request

defineOutboundCollaboration : Api.Configuration -> BoundedContextId -> Collaborator -> String -> ApiResult Collaboration2 msg
defineOutboundCollaboration url context connectionRecipient descriptionText =
  let
    api =
      Api.collaborations

    connectionInitiator = Collaborator.BoundedContext context

    request toMsg =
      Http.post
      { url = api |> Api.url url |> Url.toString
      , body = Http.jsonBody <|
              modelEncoder2 
                connectionInitiator
                connectionRecipient 
                (if String.isEmpty descriptionText then Nothing else Just descriptionText) 
                Nothing
      , expect = Http.expectJson toMsg modelDecoder
      }
    in
      request

defineRelationshipType : Api.Configuration -> CollaborationId ->  RelationshipType -> ApiResult Collaboration2 msg
defineRelationshipType url collaboration relationshipType =
  let
    api =
      collaboration |> Api.collaboration 

    request toMsg =
      Http.request
      { method = "PATCH"
      , url = api |> Api.url url |> Url.toString
      , body = Http.jsonBody <|
          Encode.object [ ("relationship", RelationshipType.encoder relationshipType) ]
      , expect = Http.expectJson toMsg modelDecoder
      , timeout = Nothing
      , tracker = Nothing
      , headers = []
      }
  in
    request



isInboundCollaboratoration : Collaborator -> Collaboration2 -> Bool
isInboundCollaboratoration collaborator (Collaboration2 collaboration) =
  collaboration.recipient == collaborator
    

areCollaborating : Collaborator -> Collaboration2 -> Bool
areCollaborating collaborator (Collaboration2 collaboration) =
  -- case collaboration.relationship of
  --   Symmetric _ p1 p2 ->
  --     p1 == collaborator || p2 == collaborator
  --   UpstreamDownstream (CustomerSupplierRole { customer, supplier }) ->
  --     supplier == collaborator || customer == collaborator
  --   UpstreamDownstream (UpstreamDownstreamRole (up,_) (down,_)) ->
  --     down == collaborator || up == collaborator
  --   Octopus (up,_) downs ->
  --     up == collaborator || (downs |> List.any (\(down,_) -> down == collaborator))
  --   Unknown p1 p2 ->
  --     p1 == collaborator || p2 == collaborator
  collaboration.initiator == collaborator || collaboration.recipient == collaborator


isCollaborator : Collaborator -> Collaboration2 -> Maybe CollaborationType
isCollaborator collaborator collaboration =
  case (areCollaborating collaborator collaboration, isInboundCollaboratoration collaborator collaboration) of
    (True, True) -> 
      Just <| Inbound collaboration
    (True, False) ->
      Just <| Outbound collaboration
    _ ->
      Nothing

id : Collaboration2 -> CollaborationId
id (Collaboration2 collaboration) =
  collaboration.id

relationship : Collaboration2 -> Maybe RelationshipType
relationship (Collaboration2 collaboration) =
  collaboration.relationship

initiator : Collaboration2 -> Collaborator
initiator (Collaboration2 collaboration) =
  collaboration.initiator


recipient : Collaboration2 -> Collaborator
recipient (Collaboration2 collaboration) =
  collaboration.recipient


otherCollaborator : Collaborator -> Collaboration2 -> Collaborator
otherCollaborator knownCollaborator (Collaboration2 collaboration) =
  if collaboration.recipient == knownCollaborator
  then collaboration.initiator
  else collaboration.recipient

description : Collaboration2 -> Maybe String
description (Collaboration2 collaboration) =
  collaboration.description

idFieldDecoder : Decoder CollaborationId
idFieldDecoder =
  Decode.field "id" ContextMapping.idDecoder

modelDecoder : Decoder Collaboration2
modelDecoder =
  ( Decode.succeed CollaborationInternal2
    |> JP.custom idFieldDecoder
    |> JP.required "description" (Decode.nullable Decode.string)
    |> JP.required "initiator" Collaborator.decoder
    |> JP.required "recipient" Collaborator.decoder
    |> JP.required "relationship" (Decode.nullable RelationshipType.decoder)
  ) |> Decode.map Collaboration2


modelEncoder2 : Collaborator -> Collaborator -> Maybe String -> Maybe RelationshipType -> Encode.Value
modelEncoder2 connectionInitiator connectionRecipient descriptionValue relationshipType =
  Encode.object
    [ ("description", maybeEncoder Encode.string descriptionValue)
    , ("initiator", Collaborator.encoder connectionInitiator)
    , ("recipient", Collaborator.encoder connectionRecipient)
    , ("relationship", maybeEncoder RelationshipType.encoder relationshipType)
    ]


maybeEncoder : (t -> Encode.Value) -> Maybe t -> Encode.Value
maybeEncoder encoder value =
  case value of
    Just v -> encoder v
    Nothing -> Encode.null