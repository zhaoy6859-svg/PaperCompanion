// Read-only tools the model may call. Execution and validation stay in the app.

export const PAPER_TOOLS = [{
  type: 'function',
  function: {
    name: 'get_paper_page',
    description: '读取当前论文某一页的正文。需要核对原文细节、公式或页码时调用。页码从 1 开始。',
    parameters: {
      type: 'object',
      properties: {
        page_number: {type: 'integer', description: '页码，从 1 开始'}
      },
      required: ['page_number'],
      additionalProperties: false
    }
  }
}];

export function getPaperPage(pages, rawArguments) {
  let args;
  try {
    args = typeof rawArguments === 'string'
      ? (rawArguments.trim() ? JSON.parse(rawArguments) : {})
      : (rawArguments || {});
  } catch {
    return {error: '工具参数不是合法 JSON'};
  }
  const page = Number(args.page_number);
  if (!Number.isInteger(page)) return {error: 'page_number 必须是整数'};
  if (!Array.isArray(pages) || page < 1 || page > pages.length) {
    return {error: `页码 ${page} 超出范围（1-${Array.isArray(pages) ? pages.length : 0}）`, page_count: Array.isArray(pages) ? pages.length : 0};
  }
  return {page, page_count: pages.length, text: String(pages[page - 1] || '').trim().slice(0, 6000)};
}

export async function runToolLoop({messages, tools, callModel, executeTool, maxSteps = 4, isCancelled = () => false, onTool = () => {}}) {
  const conversation = messages.slice();
  for (let step = 0; step <= maxSteps; step++) {
    if (isCancelled()) throw Object.assign(new Error('已取消'), {code: 'ABORTED'});
    const reply = await callModel(conversation, tools);
    if (isCancelled()) throw Object.assign(new Error('已取消'), {code: 'ABORTED'});
    const calls = (reply.toolCalls || []).filter(call => call?.function?.name);
    if (!calls.length) return {text: reply.text || '', messages: conversation, steps: step};
    if (step === maxSteps) return {text: reply.text || '', messages: conversation, steps: step, truncated: true};
    const normalized = calls.map((call, index) => ({
      id: call.id || `call_${step}_${index}`,
      type: 'function',
      function: {name: call.function.name, arguments: call.function.arguments || '{}'}
    }));
    conversation.push({role: 'assistant', content: reply.text || '', tool_calls: normalized});
    for (const call of normalized) {
      if (isCancelled()) throw Object.assign(new Error('已取消'), {code: 'ABORTED'});
      const result = await executeTool(call);
      onTool(call, result);
      conversation.push({role: 'tool', tool_call_id: call.id, content: JSON.stringify(result)});
    }
  }
  return {text: '', messages: conversation, steps: maxSteps};
}
