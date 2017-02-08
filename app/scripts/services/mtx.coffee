'use strict'

###*
###
angular.module('swarmApp').factory 'KongregateMtx', ($q, game, kongregate) -> class KongregateMtx
  constructor: (@buyPacks) ->
    @buyPacksByName = _.keyBy @buyPacks, 'name'
  packs: -> $q (resolve, reject) =>
    #kongregate.kongregate.mtx.requestItemList [], (res) =>
    #  resolve(res)
    # TODO use kongregate's item list
    return resolve(@buyPacks)
  pull: -> $q (resolve, reject) =>
    kongregate.onLoad.then =>
      if kongregate.kongregate.services.isGuest()
        reject 'Please log in to buy crystals.'
      kongregate.kongregate.mtx.requestUserItemList null, (res, error) =>
        try
          if !res.success
            return reject(res)
          changed = false
          for purchase in res.data
            if !game.session.state.mtx?.kongregate?[purchase.id]
              #session.state.mtx.kongregate[purchase.id] = true
              # TODO use kongregate's item list
              pack = @buyPacksByName[purchase.identifier]
              if pack?
                game.unit('crystal')._addCount pack['pack.val']
                game.session.state.mtx ?= {}
                game.session.state.mtx.kongregate ?= {}
                game.session.state.mtx.kongregate[purchase.id] = true
                changed = true
          resolve({changed: changed})
        catch e
          reject(e)
  buy: (name) -> $q (resolve, reject) =>
    kongregate.onLoad.then =>
      if kongregate.kongregate.services.isGuest()
        reject 'Please log in to buy crystals.'
      kongregate.kongregate.mtx.purchaseItems [name], (success) =>
        if success
          @pull()
          resolve(success)
        else
          reject(success)

# Playfab error checking within a promise.
# usage: PlayFabClientAPI.blah {}, wrapPlayfab reject, 'blah', (result) =>
wrapPlayfab = (reject, name, fn) => (result) =>
  try
    console.debug 'PlayFabClientSDK.'+name, result
    if !result? or result.status != 'OK'
      return reject result
    return fn result
  catch e
    console.error e
    reject e
 
# https://community.playfab.com/questions/638/208252737-PlayFab-and-PayPal-integration-problem.html
angular.module('swarmApp').factory 'PaypalMtx', ($q, game) -> class PaypalMtx
  # Playfab uses Paypal as its backend here
  constructor: (@buyPacks) ->
    @buyPacksByName = _.keyBy @buyPacks, 'name'
  packs: -> $q (resolve, reject) =>
    # TODO use playfab's item list
    return resolve(@buyPacks)
  _confirm: -> $q (resolve, reject) =>
    if game.session.state.mtx?.paypal?.pendingOrderId?
      console.debug 'paypal pendingorderid', game.session.state.mtx.paypal.pendingOrderId
      PlayFabClientSDK.ConfirmPurchase
        OrderId: game.session.state.mtx.paypal.pendingOrderId
        wrapPlayfab reject, 'ConfirmPurchase', (result) =>
          if !result.data.Status != 'Succeeded'
            return reject result
          game.session.state.mtx.paypal.pendingOrderId = null
          return resolve result
    else
      return resolve null
  pull: -> $q (resolve, reject) =>
    @_confirm().then =>
      PlayFabClientSDK.GetUserInventory {},
        wrapPlayfab reject, 'GetUserInventory', (result) =>
          changed = false
          for item in result.data.Inventory
            if !game.session.state.mtx.paypal[item.ItemInstanceId]
              # TODO use playfab's item list
              pack = @buyPacksByName[purchase.identifier]
              if pack?
                game.unit('crystal')._addCount pack['pack.val']
                game.session.state.mtx ?= {}
                game.session.state.mtx.kongregate ?= {}
                game.session.state.mtx.kongregate[purchase.id] = true
                changed = true
          resolve({changed: changed})
  buy: (name) -> $q (resolve, reject) =>
    PlayFabClientSDK.StartPurchase
      CatalogVersion: 'scratch',
      Items: [{
        ItemId: "One"
        Quantity: 1
      }]
      wrapPlayfab reject, 'StartPurchase', (result) =>
        PlayFabClientSDK.PayForPurchase
          OrderId: result.data.OrderId
          ProviderName: "PayPal"
          Currency: "RM"
          wrapPlayfab reject, 'PayForPurchase', (result) =>
            game.session.state.mtx ?= {}
            game.session.state.mtx.paypal ?= {}
            game.session.state.mtx.paypal.pendingOrderId = result.data.OrderId
            game.save()
            document.location = result.data.PurchaseConfirmationPageURL

angular.module('swarmApp').factory 'DisabledMtx', ($q, game) -> class KongregateMtx
  fail: -> $q (resolve, reject) =>
    reject 'Payments are unavailable right now. Please try again later.'
  packs: -> @fail()
  pull: -> @fail()
  buy: -> @fail()

angular.module('swarmApp').factory 'Mtx', ($q, game, isKongregate, KongregateMtx, PaypalMtx) -> class Mtx
  constructor: (buyPacks, @toEnergy) ->
    if isKongregate()
      @backend = new KongregateMtx buyPacks
    else
      #@backend = new DisabledMtx()
      @backend = new PaypalMtx buyPacks
  packs: -> @backend.packs()
  pull: ->
    @backend.pull().then (res) ->
      if res.changed
        game.save()
      return res
  buy: (name) -> @backend.buy(name)

  convert: (conversion) ->
    crystal = game.unit('crystal')
    mtxEnergy = game.unit('mtxEnergy')
    energy = game.unit('energy')
    # no need to check if energy will be below max - mtxEnergy increases the max
    # so I (and players) don't have to think about that
    if (crystal.count()).greaterThan(conversion.crystal)
      crystal._subtractCount conversion.crystal
      mtxEnergy._addCount conversion.energy
      energy._addCount conversion.energy
    else
      throw new Error 'Not enough crystal.'

###*
 # @ngdoc service
 # @name swarmApp.mtx
 # @description
 # # mtx
 # Factory in the swarmApp.
###
angular.module('swarmApp').factory 'mtx', (Mtx, spreadsheet) ->
  new Mtx spreadsheet.data.mtx.elements, spreadsheet.data.mtxToEnergy.elements
