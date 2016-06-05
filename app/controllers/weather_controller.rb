# -*- coding: utf-8 -*-
require 'uri'
require 'net/http'
require 'savon'
require 'xmlrpc/client'

class WeatherController < ApplicationController
  # Déclaration du Endpoint SOAP
  soap_service namespace: 'urn:WashOut'

  # Avant toute action du Controller, essaye d'authentifier l'utilisateur
  before_action :authentication

  # Déclaration de la méthode SOAP
  soap_action 'by_lat_lon',
              # Arguments attendus
              args: {
                login: :string,
                password: :string,
                lat: :double,
                lon: :double,
                authent_ip: :string,
                authent_method: :string
              },
              # Type de retour
              return: :string
  def by_lat_lon
    # Client pour le WebService RPC
    rpc_client = XMLRPC::Client.new 'localhost', '/', 1234

    # Appel de la méthode du serveur JSON-RPC
    # Géolocalise une lat/lon et renvoi une ville et son pays
    city_info = JSON.parse rpc_client.call('rpc_webservice.lat_lon_info', params[:lat], params[:lon])
    # ap city_info

    # Message d'erreur si pas de ville trouvée
    render soap: 'City not found' if city_info.blank?

    # Client SOAP pour trouver la météo d'une ville
    reverse_geoloc_client = Savon.client do
      # URL du WSDL
      wsdl 'http://www.webservicex.net/globalweather.asmx?WSDL'
      convert_request_keys_to :camelcase
    end

    # Récupération de la météo de la ville
    dirty_weather = reverse_geoloc_client.call :get_weather, message: { 'CityName': city_info['city'], 'CountryName': city_info['country'] }
    # ap dirty_weather
    # Formate le retour du WebService
    city_weather = clean_dirty_weather_response dirty_weather.body
    # ap city_weather

    response = city_weather

    # Récupération du niveau de CO2 de la ville
    co2 = rpc_client.call('rpc_webservice.co2', params[:lat].to_s[0..3], params[:lon].to_s[0..3])
    # Récupération du niveau d'UV de la ville
    uv = rpc_client.call('rpc_webservice.uv', params[:lat].to_s[0..2], params[:lon].to_s[0..2])

    # Ajout du CO2 et des UVs dans le Hash global de réponse
    response['CurrentWeather']['CO2'] = co2 if co2.present?
    response['CurrentWeather']['UV'] = uv if uv.present?
    # ap response

    # Retourne un XML
    render soap: response.to_xml
  end

  private
    # Appel au serveur d'authentification
    def authentication
      # Vérification de la présence des paramètres
      if params[:login].blank? || params[:password].blank?
        render soap: 'Login and password are required'
      end

      # Vérification de la présence des paramètres
      if params[:authent_ip].blank? || params[:authent_method].blank?
        render soap: 'Authentication server IP and method are required'
      end

      authentication_params = { login: params[:login], password: params[:password] }
      authentication_url = URI.parse "http://#{params[:authent_ip]}/#{params[:authent_method]}"
      authentication_response = Net::HTTP.post_form authentication_url, authentication_params

      token = JSON.parse(authentication_response.body).dig('token') if authentication_response.present?

      # Message d'erreur si l'authentification a échouée
      render soap: 'Authentication failed. Wrong password' if token.blank?
    end

    # Formate le retour de l'appel SOAP
    def clean_dirty_weather_response response
      city_weather = response.dig :get_weather_response, :get_weather_result
      if city_weather.present?
        city_weather = city_weather.to_s.gsub /\n/, ''

        Hash.from_xml(city_weather.to_s.gsub "<?xml version=\"1.0\" encoding=\"utf-16\"?>", '')
      else
        nil
      end
    end
end
