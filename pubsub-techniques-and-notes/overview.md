# publisher: This is just a machine (or server) that publishes events

# topic: this is just a ? and topic is just a topic and it doesn't handle the incoming events from publisher or aware which subscriber(s) are listening to which topic

# channel: channele is just a subcategory or tag 

# subscriber : who is subscribed to a topic (category e.g. `fintech`) and/or channel (tags or subcategories e.g. `fintech_premium`)

# broker: Since, topic is just a topic (nothing more, nothingl less), so when incoming events are received from published , there has to be something that handles it and then know which topic it should be forwared to and what subscriber are listening to that exact topic, which is what `broker` does

# router :



## fire and forget: When message are being sent to subscribers, if any of the subscribers aren't available at that time, then thant subscriber won't get that message or however many messages are deliveed in that time and Redis won't replay or notify either. So, a subscriber will get the message(s) if active or avaialble otherwise not (and by default there is no replay or notification about the missed messages)

## Fan out: When a channel receives an event, however many subscriber are attached to it, they will all get it , no subscribers can't filer out or exclude any message by any way

