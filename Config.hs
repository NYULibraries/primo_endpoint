{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Config
  ( Collection(..)
  , Collections
  , Config(..)
  , loadCollection
  ) where

import qualified Data.Aeson.Types as JSON
import qualified Data.HashMap.Strict as HM
import           Data.Maybe (fromMaybe)
import           Data.Monoid ((<>))
import qualified Data.Text as T
import           Data.Time.Clock (NominalDiffTime)
import qualified Data.Vector as V
import           System.FilePath ((</>), (<.>))

import           Util
import           Document
import           Fields
import           FDA

type Interval = NominalDiffTime

data Source
  = SourceFDA
    { _fdaCollectionId :: Int
    }
  deriving (Show)

data Collection = Collection
  { collectionSource :: Source
  , collectionCache :: FilePath
  , collectionInterval :: Interval
  , collectionName :: Maybe T.Text
  , collectionFields :: Generators
  }

type Collections = HM.HashMap T.Text Collection

data Config = Config
  { configCollections :: Collections
  , configCache :: FilePath
  }

-- |@parseSource collection source_type@
parseSource :: JSON.Object -> T.Text -> JSON.Parser Source
parseSource o "FDA" = SourceFDA <$> o JSON..: "id"
parseSource _ s = fail $ "Unknown collection source: " ++ show s

-- |@parseCollection generators templates key value@
parseCollection :: Interval -> Generators -> HM.HashMap T.Text Generators -> FilePath -> JSON.Value -> JSON.Parser Collection
parseCollection int gen tpl cache = JSON.withObject "collection" $ \o -> do
  s <- parseSource o =<< o JSON..: "source"
  i <- o JSON..:? "interval"
  n <- o JSON..:? "name"
  f <- parseGenerators gen =<< o JSON..:? "fields" JSON..!= JSON.Null
  t <- withArrayOrNullOrSingleton (foldMapM getTemplate) =<< o JSON..:? "template" JSON..!= JSON.Null
  return Collection
    { collectionCache = cache
    , collectionSource = s
    , collectionInterval = fromMaybe int i
    , collectionName = n
    , collectionFields = f <> t
    }
  where
  getTemplate = JSON.withText "template name" $ \s ->
    maybe (fail $ "Undefined template: " ++ show s) return $ HM.lookup s tpl

instance JSON.FromJSON Config where
  parseJSON = JSON.withObject "config" $ \o -> do
    i <- o JSON..: "interval"
    d <- o JSON..: "cache"
    g <- o JSON..:? "generators" JSON..!= mempty
    t <- withObjectOrNull "templates" (mapM $ parseGenerators g) =<< o JSON..:? "templates" JSON..!= JSON.Null
    c <- JSON.withObject "collections" (HM.traverseWithKey
        $ parseCollection i g t . (d </>) . (<.> "json") . T.unpack)
      =<< o JSON..: "collections"
    return Config
      { configCollections = c
      , configCache = d </> "json"
      }

loadSource :: Source -> IO Documents
loadSource (SourceFDA i) = loadFDA i

loadCollection :: Collection -> IO Documents
loadCollection Collection{..} =
  V.map (mapMetadata $ generateFields collectionFields) <$> loadSource collectionSource
