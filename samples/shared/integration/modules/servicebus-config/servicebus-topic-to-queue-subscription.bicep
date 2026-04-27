targetScope = 'resourceGroup'

param serviceBusName string
param topicSubscription object

resource serviceBus 'Microsoft.ServiceBus/namespaces@2021-11-01' existing = {
  name: serviceBusName
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' existing = {
  parent: serviceBus
  name: topicSubscription.forwardTo
}

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2021-11-01' existing = {
  parent: serviceBus
  name: topicSubscription.topic
}

resource serviceBusTopicSubscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-01-01-preview' = {
  #disable-next-line use-parent-property
  name: '${serviceBus.name}/${take(topicSubscription.topic, 63)}/${topicSubscription.subscription}'
  dependsOn: [
    serviceBusTopic
    serviceBusQueue
  ]
  properties: {
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    defaultMessageTimeToLive: 'P14D'
    forwardTo: take(topicSubscription.forwardTo, 63)
    maxDeliveryCount: 1
    requiresSession: false
    status: 'Active'
  }
}

resource serviceBusTopicSubscriptionsFilterRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: topicSubscription.rule.name
  parent: serviceBusTopicSubscriptions
  properties: {
    filterType: topicSubscription.rule.type
    sqlFilter: {
      sqlExpression: topicSubscription.rule.filter
      compatibilityLevel: 20
      requiresPreprocessing: false
    }
  }
}
