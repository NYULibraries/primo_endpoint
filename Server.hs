{-# LANGUAGE OverloadedStrings #-}
module Server
  ( server
  ) where

import           Control.Monad (guard)
import qualified Data.ByteString.Char8 as BSC
import qualified Data.HashMap.Strict as HMap
import           Data.Maybe (mapMaybe)
import qualified Data.Text.Encoding as TE (decodeUtf8)
import           Data.Time.Clock (UTCTime, getCurrentTime)
import           Data.Time.Format (formatTime, defaultTimeLocale)
import           Network.HTTP.Types (ok200, badRequest400, notFound404, methodNotAllowed405, hAccept, hContentType, hLastModified, hDate)
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Middleware.RequestLogger as Log
import           Network.Wai.Parse (parseHttpAccept)
import           Text.Blaze.Html.Renderer.Utf8 (renderHtmlBuilder)

import           Config
import           Cache
import           Output.Primo
import           View

formatDate :: UTCTime -> BSC.ByteString
formatDate = BSC.pack . formatTime defaultTimeLocale "%a, %d %b %Y %T GMT"

serve :: Config -> Wai.Request -> IO Wai.Response
serve conf req = maybe
  (return $ Wai.responseLBS (if Wai.pathInfo req == [] then badRequest400 else notFound404) [] mempty)
  (\c -> case Wai.requestMethod req of
    "GET" -> do
      -- load documents (possibly in "orig", untranslated form)
      t <- getCurrentTime
      let t' = if refresh then Nothing else Just t
      d <- maybe
        (generateCollection conf t' c)
        (loadCollection conf t')
        $ guard orig >> c
      return $ Wai.mapResponseHeaders (++
        [ (hLastModified, formatDate t) -- XXX
        , (hDate, formatDate t)
        ]) $ if html
        then Wai.responseBuilder ok200
          [ (hContentType, "text/html;charset=utf-8") ]
          $ renderHtmlBuilder $ view conf c d orig (Wai.queryString req)
        else Wai.responseBuilder ok200
          [ (hContentType, "application/json") ]
          $ outputPrimo d
    _ -> return $ Wai.responseLBS methodNotAllowed405
      [(hAccept, "GET")] mempty)
  coll
  where
  query = Wai.queryString req
  getq k = lookup k query
  boolq k = case getq k of
    Just Nothing -> True
    Just (Just "1") -> True
    Just (Just "on") -> True
    Just (Just "true") -> True
    _ -> False
  coll = case (Wai.pathInfo req, getq "collection") of
    ([c], _) -> getcoll c
    ([], Just (Just c)) | not (BSC.null c) -> getcoll $ TE.decodeUtf8 c
    ([], _) -> Just Nothing -- all
    _ -> Nothing
  getcoll c = Just <$> HMap.lookup c (configCollections conf)
  refresh = boolq "refresh"
  orig = boolq "orig"
  accept = foldMap parseHttpAccept $ lookup hAccept $ Wai.requestHeaders req
  html = not (boolq "json") && (boolq "html" ||
    head (mapMaybe (\t -> case t of
      "text/html" -> Just True
      "application/json" -> Just False
      _ -> Nothing) accept ++ [False]))

server :: Int -> Bool -> Config -> IO ()
server port logging conf = Warp.run port
  $ (if logging then Log.logStdout else id)
  $ (>>=) . serve conf
