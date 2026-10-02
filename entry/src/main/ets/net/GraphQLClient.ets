import http from '@ohos.net.http';
import { graphqlURL } from '../model/Models';
import { AppSettings } from './AppSettings';
import { NetLog } from './NetLog';

// GraphQL 错误
export class GraphQLError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

// 轻量 GraphQL 客户端（无第三方依赖）
// 硬超时：URLSession 在鸿蒙不存在连接池吊死问题（每次 createHttp 独立连接），
// 但保留硬超时兜底与链路失败重试一次，保证 loading 状态一定复位。
export class GraphQLClient {
  url: string;
  apiKey: string;
  profileName: string;
  static hardTimeout: number = 10000;   // 常规请求硬超时
  static longTimeout: number = 120000;  // 刮削 / 识别长请求

  constructor(baseURL: string, apiKey: string, profileName: string) {
    this.url = graphqlURL(baseURL);
    this.apiKey = apiKey;
    this.profileName = profileName;
  }

  // 发送 GraphQL 请求并返回 data 节点（ESObject 由调用方 as 到具体类型）
  async send(query: string, variables: Record<string, Object> = {}, timeout: number = GraphQLClient.hardTimeout): Promise<ESObject> {
    const bodyObj: Record<string, Object> = { 'query': query };
    if (Object.keys(variables).length > 0) {
      bodyObj['variables'] = variables;
    }
    const body = JSON.stringify(bodyObj);

    const doOnce = (): Promise<ESObject> => {
      return new Promise<ESObject>((resolve, reject) => {
        const req = http.createHttp();
        const timer = setTimeout(() => {
          req.destroy();
          reject(new GraphQLError(-1, '请求超时（超过 ' + (timeout / 1000).toString() + 's 无响应）'));
        }, timeout + 2000);

        const header: Record<string, string> = { 'Content-Type': 'application/json' };
        if (this.apiKey !== '') {
          header['ApiKey'] = this.apiKey;
        }

        req.request(this.url, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 10000,
          readTimeout: timeout
        }).then((resp) => {
          clearTimeout(timer);
          const code = resp.responseCode;
          const resultStr = resp.result as string;
          if (code !== 200) {
            NetLog.instance.record('GraphQL', 'ERROR', this.profileName + ' 请求失败',
              'HTTP ' + code.toString() + ' · ' + resultStr.substring(0, 200));
            req.destroy();
            reject(new GraphQLError(code, 'HTTP ' + code.toString() + '：' + resultStr.substring(0, 200)));
            return;
          }
          let obj: ESObject = JSON.parse(resultStr);
          const data: ESObject = obj['data'];
          if (data === undefined || data === null) {
            const errs = obj['errors'];
            let msg = 'Stash 返回错误';
            if (Array.isArray(errs) && errs.length > 0) {
              msg = errs[0]['message'] as string;
            }
            NetLog.instance.record('GraphQL', 'ERROR', this.profileName + ' 业务错误', msg);
            req.destroy();
            reject(new GraphQLError(-3, msg));
            return;
          }
          NetLog.instance.record('GraphQL', 'INFO', this.profileName + ' 查询成功');
          req.destroy();
          resolve(data);
        }).catch((err) => {
          clearTimeout(timer);
          let msg = '网络错误';
          if (err !== null && err !== undefined && err.message !== undefined) {
            msg = err.message;
          }
          NetLog.instance.record('GraphQL', 'ERROR', this.profileName + ' 链路失败', msg);
          req.destroy();
          reject(new GraphQLError(-4, msg));
        });
      });
    };

    try {
      return await doOnce();
    } catch (e) {
      // 链路失败自动重试一次（mutation 不重试，避免重复写入）
      const isMutation = query.trim().startsWith('mutation');
      const ge = e as GraphQLError;
      if (!isMutation && ge !== null && (ge.code === -1 || ge.code === -4)) {
        NetLog.instance.record('GraphQL', 'WARN', this.profileName + ' 重试一次', ge.message);
        try {
          return await doOnce();
        } catch (e2) {
          throw e2;
        }
      }
      throw e;
    }
  }
}

// 客户端工厂
export function makeClient(): GraphQLClient {
  const settings = AppSettings.instance;
  return new GraphQLClient(settings.activeBaseURL(), settings.apiKey(), settings.profileName());
}

// 实测连接：登录页用。任何 HTTP 应答都算可达，仅网络层异常为失败
export async function probeGraphQL(baseURL: string, apiKey: string, query: string, timeout: number): Promise<string> {
  const client = new GraphQLClient(baseURL, apiKey, '登录探测');
  try {
    await client.send(query, {}, timeout);
    return '';
  } catch (e) {
    const ge = e as GraphQLError;
    return ge !== null ? ge.message : '未知错误';
  }
}
