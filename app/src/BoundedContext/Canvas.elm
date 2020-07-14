module BoundedContext.Canvas exposing (..)

import Json.Encode as Encode
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as JP

import Http
import Url exposing (Url)

import Key as Key
import BoundedContext exposing (BoundedContext)
import BoundedContext.Dependency as Dependency
import BoundedContext.StrategicClassification as StrategicClassification exposing(StrategicClassification)
import BoundedContext.Message as Message exposing (Messages)

-- MODEL

type alias BusinessDecisions = String
type alias UbiquitousLanguage = String
type alias ModelTraits = String

type alias BoundedContextCanvas =
  { boundedContext : BoundedContext
  , description : String
  , classification : StrategicClassification
  , businessDecisions : BusinessDecisions
  , ubiquitousLanguage : UbiquitousLanguage
  , modelTraits : ModelTraits
  , messages : Messages
  , dependencies : Dependencies
  }

-- TODO: should this be part of the BCC or part of message?
type alias Dependencies =
  { suppliers : Dependency.DependencyMap
  , consumers : Dependency.DependencyMap
  }



initDependencies : Dependencies
initDependencies =
  { suppliers = Dependency.emptyDependencies
  , consumers = Dependency.emptyDependencies
  }

init: BoundedContext -> BoundedContextCanvas
init context =
  { boundedContext = context
  , description = ""
  , classification = StrategicClassification.noClassification
  , businessDecisions = ""
  , ubiquitousLanguage = ""
  , modelTraits = ""
  , messages = Message.noMessages
  , dependencies = initDependencies
  }

-- encoders

dependenciesEncoder : Dependencies -> Encode.Value
dependenciesEncoder dependencies =
  Encode.object
    [ ("suppliers", Dependency.dependencyEncoder dependencies.suppliers)
    , ("consumers", Dependency.dependencyEncoder dependencies.consumers)
    ]

modelEncoder : BoundedContextCanvas -> Encode.Value
modelEncoder canvas =
  Encode.object
    [ ("name", Encode.string (canvas.boundedContext |> BoundedContext.name))
    , ("key",
        case canvas.boundedContext |> BoundedContext.key of
          Just v -> Key.keyEncoder v
          Nothing -> Encode.null
      )
    , ("description", Encode.string canvas.description)
    , ("classification", StrategicClassification.encoder canvas.classification)
    , ("businessDecisions", Encode.string canvas.businessDecisions)
    , ("ubiquitousLanguage", Encode.string canvas.ubiquitousLanguage)
    , ("modelTraits", Encode.string canvas.modelTraits)
    , ("messages", Message.messagesEncoder canvas.messages)
    , ("dependencies", dependenciesEncoder canvas.dependencies)
    ]

maybeStringDecoder : (String -> Maybe v) -> Decoder (Maybe v)
maybeStringDecoder parser =
  Decode.oneOf
    [ Decode.null Nothing
    , Decode.map parser Decode.string
    ]

dependenciesDecoder : Decoder Dependencies
dependenciesDecoder =
  Decode.succeed Dependencies
    |> JP.optional "suppliers" Dependency.dependencyDecoder Dependency.emptyDependencies
    |> JP.optional "consumers" Dependency.dependencyDecoder Dependency.emptyDependencies



modelDecoder : Decoder BoundedContextCanvas
modelDecoder =
  Decode.succeed BoundedContextCanvas
    |> JP.custom BoundedContext.modelDecoder
    |> JP.optional "description" Decode.string ""
    |> JP.optional "classification" StrategicClassification.decoder StrategicClassification.noClassification
    |> JP.optional "businessDecisions" Decode.string ""
    |> JP.optional "ubiquitousLanguage" Decode.string ""
    |> JP.optional "modelTraits" Decode.string ""
    |> JP.optional "messages" Message.messagesDecoder Message.noMessages
    |> JP.optional "dependencies" dependenciesDecoder initDependencies
