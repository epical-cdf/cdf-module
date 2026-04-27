targetScope = 'resourceGroup'

param domainName string
param serviceName string
param serviceBusName string
param serviceBusConfig object = loadJsonContent('servicebus.sample.config.json')

var queues = serviceBusConfig.queues
var topics = serviceBusConfig.topics
var topicSubscriptions = serviceBusConfig.topicSubscriptions

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusName
}

resource serviceBusQueues 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = [
  for queue in queues: {
    parent: serviceBus
    name: take(queue.name, 63)
    properties: {
      lockDuration: 'PT30S'
      requiresDuplicateDetection: false
      requiresSession: false
      defaultMessageTimeToLive: 'PT12H'
      deadLetteringOnMessageExpiration: false
      enableBatchedOperations: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
      maxDeliveryCount: 10
      status: 'Active'
      enablePartitioning: false
      enableExpress: false
    }
  }
]

resource serviceBusTopics 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = [
  for topic in topics: {
    parent: serviceBus
    name: take(topic.name, 63)
    properties: {
      requiresDuplicateDetection: false
      defaultMessageTimeToLive: 'PT12H'
      enableBatchedOperations: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
      status: 'Active'
      autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
      enablePartitioning: false
      enableExpress: false
    }
  }
]

module modServiceBusTopicSubscriptions './servicebus-topic-to-queue-subscription.bicep' = [
  for (topicSubscription, index) in topicSubscriptions: {
    name: take('modServiceBusTopicSubscriptions-${index}-${replace(topicSubscription.subscription, '.', '')}', 64)
    dependsOn: [
      serviceBusTopics
      serviceBusQueues
    ]
    params: {
      serviceBusName: serviceBus.name
      topicSubscription: topicSubscription
    }
  }
]
